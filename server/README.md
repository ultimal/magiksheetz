# WebSheets local command server (PowerShell)

A tiny **loopback-only** HTTP server that lets the WebSheets page send a command,
runs it in an isolated child process, and returns `stdout` / `stderr` / `exitCode`.

> ⚠️ This executes commands on your machine. It's meant for **your own local use**.
> It binds to `localhost` only, requires a secret token, and checks the request
> `Origin`. Keep the token private, and consider narrowing `Invoke-ShellCommand`
> to an allow-list of specific operations instead of an open shell.

## Run it

```powershell
# from the repo root
powershell -ExecutionPolicy Bypass -File .\server\websheets-server.ps1

# options
powershell -ExecutionPolicy Bypass -File .\server\websheets-server.ps1 -Port 8787 -Token my-secret -Confirm
```

On startup it prints the **token** — you pass that with every request. `-Confirm`
makes the server prompt you in its console before running each command.

## API

| Method | Path    | Auth                    | Body / Result |
|--------|---------|-------------------------|---------------|
| GET    | `/ping` | none                    | `{ ok, server, version }` |
| POST   | `/run`  | `X-WebSheets-Token` hdr | see below |

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

- **Loopback only** — listens on `http://localhost:<port>`; not reachable from the network.
- **Token** — `/run` requires the `X-WebSheets-Token` header to equal the server's token, so an arbitrary web page can't drive it.
- **Origin allow-list** — only `null` (file://), `localhost`, and `127.0.0.1` origins are accepted (defends against DNS-rebinding / other sites).
- **Isolated execution** — each command runs in a fresh child `powershell.exe`/`cmd.exe` with a timeout (`-TimeoutSeconds`, default 60), so it can't corrupt the server's own state.
- **Optional confirm** — `-Confirm` requires a keypress in the server console per command.

To lock it down further, edit `Invoke-ShellCommand` in `websheets-server.ps1` to map a small set of named actions to fixed commands rather than executing whatever string is sent.

## Calling it from the browser (example)

```js
const res = await fetch('http://localhost:8787/run', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', 'X-WebSheets-Token': TOKEN },
  body: JSON.stringify({ command: 'Get-Date', shell: 'powershell' })
});
const out = await res.json();   // { ok, exitCode, stdout, stderr, durationMs }
```

> Note: opening `index.html` via `file://` or `http://` works with this server.
> If you serve WebSheets over **HTTPS**, browsers may block the plain-`http://localhost`
> call as mixed content — serve the page over `http://` in that case.

## Notes

- First `powershell.exe` launch can be slow (cold start / antivirus). For faster
  or richer runs, install PowerShell 7 and change the launcher to `pwsh`.
- Requires Windows PowerShell 5.1+ or PowerShell 7+. No admin needed for the
  `localhost` prefix; if binding fails, pick another `-Port` or register a urlacl
  (the script prints the exact command).
