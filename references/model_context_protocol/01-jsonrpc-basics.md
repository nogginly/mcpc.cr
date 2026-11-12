# 1. JSON-RPC basics

[← Index](README.md)

Every MCP message is JSON-RPC 2.0. Three shapes:

**Request** — has `id`, expects a reply.
```json
{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}
```

**Response** — same `id`, either `result` or `error`, never both.
```json
{"jsonrpc":"2.0","id":1,"result":{"tools":[]}}
```
```json
{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"Method not found"}}
```

**Notification** — no `id`, no reply allowed.
```json
{"jsonrpc":"2.0","method":"notifications/initialized"}
```

## Error codes you will meet

| Code | Meaning | Era |
|---|---|---|
| -32700 | Parse error | all |
| -32600 | Invalid request | all |
| -32601 | Method not found | all |
| -32602 | Invalid params (also "resource not found" from 2026-07-28) | all |
| -32603 | Internal error | all |
| -32002 | Resource not found | ≤ 2025-11-25 |
| -32020 | Header mismatch | 2026-07-28 |
| -32021 | Missing required client capability | 2026-07-28 |
| -32022 | Unsupported protocol version | 2026-07-28 |

## Caveats

1. `id` may be a string or integer, never `null` in MCP. Echo it back with the same type.
2. Either side can send requests in the handshake era (the server asks the client for sampling, roots, elicitation). Your reader loop must route by shape, not assume "everything inbound is a response".
3. Batches (a JSON array of messages) existed only in 2025-03-26. Reject or tolerate them, but don't emit them.
