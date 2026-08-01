<#
  MagikSheetz local command server
  ------------------------------------------------------------------------------
  A tiny loopback-only HTTP server that lets the MagikSheetz page send a command,
  runs it in an isolated child process, and returns stdout / stderr / exit code.

  SECURITY — read this:
    * Binds to http://localhost:<port> only (never exposed to the network).
    * Every /run request must carry the shared token (printed on startup) in the
      "X-MagikSheetz-Token" header, so a random web page can't drive it.
    * The Origin header is checked (only null / localhost / 127.0.0.1 allowed).
    * Optional -Confirm prompts you in this console before each command runs.
    * This still executes commands on your machine. Run it only for your own use,
      keep the token secret, and consider editing Invoke-ShellCommand to an
      allow-list of specific operations instead of an open shell.

  USAGE:
    powershell -ExecutionPolicy Bypass -File .\magiksheetz-server.ps1
    powershell -ExecutionPolicy Bypass -File .\magiksheetz-server.ps1 -Port 8787 -Confirm

  API:
    GET  /ping                      -> { ok, server, version }
    POST /run                       -> run a command (needs X-MagikSheetz-Token)
         body: { "command": "...", "shell": "powershell"|"cmd", "cwd": "C:\\..." }
         resp: { ok, exitCode, stdout, stderr, durationMs, timedOut }
#>

[CmdletBinding()]
param(
  [int]    $Port           = 8787,
  [string] $Token          = ([guid]::NewGuid().ToString('N')),
  [int]    $TimeoutSeconds = 60,
  [switch] $Confirm
)

$ErrorActionPreference = 'Stop'

# ---- helpers ---------------------------------------------------------------

function Test-AllowedOrigin([string]$origin) {
  if ([string]::IsNullOrEmpty($origin) -or $origin -eq 'null') { return $true }   # file:// pages
  try { $u = [Uri]$origin; return @('localhost', '127.0.0.1') -contains $u.Host }
  catch { return $false }
}

function Write-JsonResponse($ctx, [int]$status, $obj, [string]$allowOrigin) {
  $res = $ctx.Response
  $res.StatusCode = $status
  if ($allowOrigin) { $res.Headers['Access-Control-Allow-Origin'] = $allowOrigin }
  $res.Headers['Vary'] = 'Origin'
  $res.Headers['Access-Control-Allow-Headers'] = 'Content-Type, X-MagikSheetz-Token'
  $res.Headers['Access-Control-Allow-Methods'] = 'POST, GET, OPTIONS'
  $json  = $obj | ConvertTo-Json -Depth 6 -Compress
  $bytes = [Text.Encoding]::UTF8.GetBytes($json)
  $res.ContentType = 'application/json; charset=utf-8'
  $res.ContentLength64 = $bytes.Length
  $res.OutputStream.Write($bytes, 0, $bytes.Length)
  $res.OutputStream.Close()
}

function Invoke-ShellCommand([string]$command, [string]$shell, [string]$cwd, [int]$timeoutSec) {
  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.UseShellExecute        = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError  = $true
  $psi.CreateNoWindow         = $true
  $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
  $psi.StandardErrorEncoding  = [Text.Encoding]::UTF8
  if ($cwd -and (Test-Path -LiteralPath $cwd)) { $psi.WorkingDirectory = $cwd }

  $batFile = $null
  if ($shell -eq 'cmd') {
    $batFile = [IO.Path]::Combine([IO.Path]::GetTempPath(), "magiksheetz_$([guid]::NewGuid().ToString('N')).cmd")
    Set-Content -LiteralPath $batFile -Value "@chcp 65001 >nul`r`n$command" -Encoding Oem
    $psi.FileName  = $env:ComSpec
    $psi.Arguments = "/c `"$batFile`""
  }
  else {
    # PowerShell via -EncodedCommand avoids all quoting problems; force UTF-8 output.
    $wrapped = "[Console]::OutputEncoding=[Text.Encoding]::UTF8; `$OutputEncoding=[Text.Encoding]::UTF8; $command"
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($wrapped))
    $psi.FileName  = (Get-Command powershell.exe).Source
    $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $enc"
  }

  $sw = [Diagnostics.Stopwatch]::StartNew()
  $p  = [System.Diagnostics.Process]::Start($psi)
  # read both streams asynchronously to avoid buffer deadlocks
  $outTask = $p.StandardOutput.ReadToEndAsync()
  $errTask = $p.StandardError.ReadToEndAsync()

  $exited = $p.WaitForExit($timeoutSec * 1000)
  if (-not $exited) {
    try { $p.Kill($true) } catch { try { $p.Kill() } catch {} }
    $sw.Stop()
    if ($batFile) { Remove-Item -LiteralPath $batFile -ErrorAction SilentlyContinue }
    return @{ ok = $false; timedOut = $true; exitCode = $null;
              stdout = ($outTask.Result); stderr = "Timed out after $timeoutSec s";
              durationMs = $sw.ElapsedMilliseconds }
  }
  $sw.Stop()
  $out = $outTask.Result
  $err = $errTask.Result
  if ($batFile) { Remove-Item -LiteralPath $batFile -ErrorAction SilentlyContinue }
  return @{ ok = ($p.ExitCode -eq 0); timedOut = $false; exitCode = $p.ExitCode;
            stdout = $out; stderr = $err; durationMs = $sw.ElapsedMilliseconds }
}

# ---- start the listener ----------------------------------------------------

$prefix = "http://localhost:$Port/"
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add($prefix)
try { $listener.Start() }
catch {
  Write-Host "Failed to start on $prefix" -ForegroundColor Red
  Write-Host $_.Exception.Message
  Write-Host "If it's an access error, try another -Port, or run once as admin:" -ForegroundColor Yellow
  Write-Host "  netsh http add urlacl url=$prefix user=$env:USERNAME"
  return
}

Write-Host ""
Write-Host "  MagikSheetz local command server" -ForegroundColor Green
Write-Host "  Listening on $prefix  (loopback only)"
Write-Host "  Token: " -NoNewline; Write-Host $Token -ForegroundColor Cyan
Write-Host "  -> Paste this token into MagikSheetz to authorize requests."
if ($Confirm) { Write-Host "  Confirm mode ON: you'll be asked before each command runs." -ForegroundColor Yellow }
Write-Host "  Press Ctrl+C to stop."
Write-Host ""

try {
  while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    try {
      $req    = $ctx.Request
      $origin = $req.Headers['Origin']

      if (-not (Test-AllowedOrigin $origin)) {
        Write-JsonResponse $ctx 403 @{ ok = $false; error = 'origin not allowed' } $null
        continue
      }
      $allowOrigin = if ($origin) { $origin } else { '*' }

      # CORS preflight
      if ($req.HttpMethod -eq 'OPTIONS') { Write-JsonResponse $ctx 204 @{} $allowOrigin; continue }

      $path = $req.Url.AbsolutePath

      if ($path -eq '/ping' -and $req.HttpMethod -eq 'GET') {
        Write-JsonResponse $ctx 200 @{ ok = $true; server = 'magiksheetz'; version = 1 } $allowOrigin
        continue
      }

      if ($path -eq '/run' -and $req.HttpMethod -eq 'POST') {
        if ($req.Headers['X-MagikSheetz-Token'] -ne $Token) {
          Write-JsonResponse $ctx 401 @{ ok = $false; error = 'invalid or missing token' } $allowOrigin
          continue
        }
        $reader = [IO.StreamReader]::new($req.InputStream, [Text.Encoding]::UTF8)
        $body   = $reader.ReadToEnd(); $reader.Close()
        try { $data = $body | ConvertFrom-Json }
        catch { Write-JsonResponse $ctx 400 @{ ok = $false; error = 'invalid JSON body' } $allowOrigin; continue }

        $command = [string]$data.command
        if ([string]::IsNullOrWhiteSpace($command)) {
          Write-JsonResponse $ctx 400 @{ ok = $false; error = 'no command provided' } $allowOrigin
          continue
        }
        $shell = if ($data.shell) { ([string]$data.shell).ToLower() } else { 'powershell' }
        if ($shell -ne 'cmd') { $shell = 'powershell' }
        $cwd = if ($data.cwd) { [string]$data.cwd } else { (Get-Location).Path }

        Write-Host ("[{0}] {1}> {2}" -f (Get-Date -Format 'HH:mm:ss'), $shell, $command)

        if ($Confirm) {
          $ans = Read-Host "  Run this command? [y/N]"
          if ($ans -notmatch '^(y|yes)$') {
            Write-JsonResponse $ctx 200 @{ ok = $false; error = 'declined at server console'; declined = $true } $allowOrigin
            continue
          }
        }

        $result = Invoke-ShellCommand $command $shell $cwd $TimeoutSeconds
        Write-JsonResponse $ctx 200 $result $allowOrigin
        continue
      }

      Write-JsonResponse $ctx 404 @{ ok = $false; error = 'not found' } $allowOrigin
    }
    catch {
      try { Write-JsonResponse $ctx 500 @{ ok = $false; error = $_.Exception.Message } '*' } catch {}
    }
  }
}
finally {
  $listener.Stop(); $listener.Close()
  Write-Host "Server stopped."
}
