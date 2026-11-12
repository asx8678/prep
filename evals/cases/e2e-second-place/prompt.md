---
description: "end to end: fix a bug that a second file repeats"
max_turns: 200
timeout_seconds: 3600
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
---

`low_stock([("bolt", 5)], 5)` in stock.py returns `[]`. Its docstring says "at most", so bolt should be listed. Fix this bug.

If you have the prep and impl skills, use the prep skill for this request and then the impl skill. Do not stop to ask me anything: where you would ask, choose the simplest reasonable answer and say what you chose. If you write a brief, save it as `.briefs/2026-11-12-000000-task.md` without waiting for me, keep no record of the task, and implement it in this conversation.
