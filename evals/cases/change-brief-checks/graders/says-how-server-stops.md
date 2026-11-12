---
type: llm
focus: { source: file, path: .briefs/2026-11-12-000000-add-health.md }
---

This is a task brief. Look only at its Proof section, and in it only at the checks for the implementing session, not those after deploy.
FAIL if any of those checks starts the server (`python3 server.py`) or a watch mode and does not say how it is stopped.
PASS if every one of those checks ends on its own, or says how the server or watch mode it starts is stopped, for example with `kill`, `timeout`, or "then stop the server".
