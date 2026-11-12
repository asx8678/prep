---
type: llm
focus: { source: file, path: .briefs/2026-11-12-000000-add-health.md }
---

This is a task brief. Look only at its Proof section, and in it only at the checks for the implementing session, not those after deploy.
FAIL if any of those checks starts the server (`python3 server.py`) or a watch mode and its command, as written, does not stop it. A separate sentence that tells the reader to stop the server does not count.
PASS if every one of those checks ends on its own: a test run, a command wrapped in `timeout`, or a command that starts the server and kills it within the same command.
