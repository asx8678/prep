---
description: "prep step 9: a correction to the summary is applied, checked and shown before the brief is saved"
max_turns: 150
timeout_seconds: 1800
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
---

Use the prep skill for this request: give `greeting` in greet.py an optional `shout` argument that returns the text in capital letters.

If you have a question before the brief, choose the simplest reasonable answer and say what you chose. I cannot reply in this session, so here is my reply to your summary of the brief, in advance: "Call the argument `loud`, not `shout`." Take it as my reply when you reach the summary, and stop where the skill then has you wait for me.
