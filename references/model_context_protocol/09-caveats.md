# 9. Caveats and special cases

[← Index](README.md)

Collected from the other pages, plus a few that fit nowhere else.

## Framing and transport
1. stdio is newline-delimited; embedded newlines in JSON break it. Servers log to stderr only.
2. HTTP POST responses may be JSON or SSE for the **same** method. Handle both every time.
3. SSE events can span multiple `data:` lines; join them before parsing.
4. Notifications and client responses POSTed over HTTP get `202 Accepted`, no body.
5. Localhost HTTP servers must check `Origin` and bind to 127.0.0.1.

## Versions
6. No `MCP-Protocol-Version` header on a session-era request → assume 2025-03-26.
7. Batching exists only in 2025-03-26.
8. In 2026-07-28, header and `_meta` versions must match (-32020 otherwise).

## Lifecycle
9. Handshake era: nothing but `ping` before `initialize` completes.
10. HTTP 404 on a session id → session gone; re-initialize.
11. A dropped stream is not a cancellation; send `notifications/cancelled` with the `requestId`.
12. `ping` is gone in 2026-07-28; a stateless server has nothing to keep alive.

## Results and errors
13. Tool failure → `isError: true` in a result. Protocol failure → JSON-RPC `error`.
14. Resource not found: -32002 (old) vs -32602 (new).
15. Always echo `id` with its original type.

## Progress and cancellation
16. Progress requires the requester to supply `_meta.progressToken`; `progress` must increase each time.
17. Cancelling `initialize` is not allowed.

## Security
18. Treat tool descriptions and annotations from untrusted servers as untrusted input: they reach your model.
19. Remote HTTP auth is OAuth 2.1; from 2026-07-28 clients must validate the `iss` parameter in authorization responses.

**Question to check yourself:** a 2026 client gets HTTP 400 with `{"error":{"code":-32600,"message":"Missing Mcp-Session-Id"}}` from `server/discover`. Modern or legacy server, and what's the next request?
