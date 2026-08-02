# MagikSheetz local command server (PowerShell)

A tiny **loopback-only** HTTP server that lets the MagikSheetz page send a command,
runs it in an isolated child process, and returns `stdout` / `stderr` / `exitCode`.

> ⚠️ This executes commands on your machine. It's meant for **your own local use**.
> It binds to `localhost` only, requires a secret token, and checks the request
> `Origin`. Keep the token private, and consider narrowing `Invoke-ShellCommand`
> to an allow-list of specific operations instead of an open shell.

## Run it

```powershell
# from the repo root
powershell -ExecutionPolicy Bypass -File .\server\magiksheetz-server.ps1

# options
powershell -ExecutionPolicy Bypass -File .\server\magiksheetz-server.ps1 -Port 8787 -Token my-secret -Confirm

# connecting from a copy of MagikSheetz hosted elsewhere, e.g. GitHub Pages
# (see "Connecting from a page hosted elsewhere" below before you need this)
powershell -ExecutionPolicy Bypass -File .\server\magiksheetz-server.ps1 -AllowedOrigins "https://youruser.github.io"

# accept connections from other machines on your network instead of just this one
# (see "Listening on the network" below before you need this)
powershell -ExecutionPolicy Bypass -File .\server\magiksheetz-server.ps1 -BindAddress 192.168.1.42
```

On startup it prints the **token** — you pass that with every request. `-Confirm`
makes the server prompt you in its console before running each command.

## API

| Method | Path    | Auth                    | Body / Result |
|--------|---------|-------------------------|---------------|
| GET    | `/ping` | none                    | `{ ok, server, version }` |
| POST   | `/run`  | `X-MagikSheetz-Token` hdr | see below |

**POST `/run`**

```json
// request body
{ "command": "Get-ChildItem | Select-Object Name", "shell": "powershell", "cwd": "C:\\temp" }
```
- `shell`: `"powershell"` (default) or `"cmd"`
- `cwd`: optional working directory

```json
// response
{ "ok": true, "exitCode": 0, "stdout": "...", "stderr": "", "durationMs": 42, "timedOut": false }
```

## Security model

- **Loopback only by default** — listens on `http://localhost:<port>`; not reachable from the network unless you pass `-BindAddress`.
- **Token** — `/run` requires the `X-MagikSheetz-Token` header to equal the server's token, so an arbitrary web page can't drive it.
- **Origin allow-list** — only `null` (file://), `localhost`, and `127.0.0.1` origins are accepted by default (defends against DNS-rebinding / other sites), plus any exact origins you add with `-AllowedOrigins`.
- **Isolated execution** — each command runs in a fresh child `powershell.exe`/`cmd.exe` with a timeout (`-TimeoutSeconds`, default 60), so it can't corrupt the server's own state.
- **Optional confirm** — `-Confirm` requires a keypress in the server console per command.

To lock it down further, edit `Invoke-ShellCommand` in `magiksheetz-server.ps1` to map a small set of named actions to fixed commands rather than executing whatever string is sent.

## Calling it from the browser (example)

```js
const res = await fetch('http://localhost:8787/run', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', 'X-MagikSheetz-Token': TOKEN },
  body: JSON.stringify({ command: 'Get-Date', shell: 'powershell' })
});
const out = await res.json();   // { ok, exitCode, stdout, stderr, durationMs }
```

> Note: opening `index.html` via `file://` or `http://` works with this server out of
> the box. Browsers treat `http://localhost` as a "trustworthy" target even from an
> HTTPS page, so this isn't blocked as mixed content — see below for what actually
> needs configuring when the page is hosted elsewhere.

## Connecting from a page hosted elsewhere (e.g. GitHub Pages)

A copy of MagikSheetz running from `https://youruser.github.io/...` still runs in
**your** browser, so it can still reach a command server on **your** machine — but
two extra checks kick in that a same-origin `file://`/`localhost` page skips:

1. **Origin allow-list.** The server rejects any `Origin` it doesn't recognize with
   a 403, and `https://youruser.github.io` isn't `localhost`/`127.0.0.1` by default.
   Fix: start the server with `-AllowedOrigins "https://youruser.github.io"` (comma-separate
   more than one). Only add origins you actually trust — anything at that origin
   running in your browser will be able to drive this server.
2. **Private Network Access.** Chromium browsers require a
   `Access-Control-Allow-Private-Network: true` response header before letting a
   page on the public internet reach a `localhost` address, even for a plain `GET`.
   The server always sends this header, so once your origin is allow-listed the
   preflight should succeed. Some Chrome versions additionally show a one-time
   "wants to access devices on your local network" permission prompt the first
   time — click **Allow**.

If it still fails, open DevTools → Network on the MagikSheetz page and check the
`OPTIONS` preflight to `/ping` or `/run`: a 403 means the origin isn't allow-listed;
a blocked/failed request after a successful-looking preflight usually means the
browser's local-network permission prompt was dismissed or never shown — reload
the page and retry.

## Listening on the network

By default `-BindAddress` is `localhost`, so the server is unreachable from other
machines even if they're on the same network. Passing your machine's LAN IP (or
`+` for all interfaces) opens it up:

```powershell
powershell -ExecutionPolicy Bypass -File .\server\magiksheetz-server.ps1 -BindAddress 192.168.1.42
```

**Think before you do this.** The only thing standing between "anyone who can
reach this port" and "runs arbitrary commands on your machine" is the token,
sent in a header over plain HTTP (no TLS) — no rate limiting, no encryption.
Only do this on a network you actually trust, prefer your specific LAN IP over
`+`, and make sure Windows Firewall doesn't allow the port from anything wider
than that. Binding to a non-loopback address usually needs a URL ACL reservation
first; if the server fails to start, it prints the exact
`netsh http add urlacl ...` command to run.

## Notes

- First `powershell.exe` launch can be slow (cold start / antivirus). For faster
  or richer runs, install PowerShell 7 and change the launcher to `pwsh`.
- Requires Windows PowerShell 5.1+ or PowerShell 7+. No admin needed for the
  `localhost` prefix; if binding fails, pick another `-Port` or register a urlacl
  (the script prints the exact command).
