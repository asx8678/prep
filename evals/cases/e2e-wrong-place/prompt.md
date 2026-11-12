---
description: "end to end: the request blames one file, the cause is in another that a third one also uses"
max_turns: 200
timeout_seconds: 3600
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
---

The invoice total is wrong: `python3 -c "import invoice; print(invoice.total([('12.5', 2)]))"` prints 2410 and should print 2500. I think invoice.total adds things up badly. Please fix invoice.py.

If you have the prep and impl skills, use the prep skill for this request and then the impl skill. Do not stop to ask me anything: where you would ask, choose the simplest reasonable answer and say what you chose. If you write a brief, save it as `.briefs/2026-11-12-000000-task.md` without waiting for me, keep no record of the task, and implement it in this conversation.
