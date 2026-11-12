---
name: impl
description: Implements a task brief written by the prep skill. Finds the newest brief in .briefs/ (or the one the user names), follows it, runs its proof commands, and reports what the brief got wrong or left out. Use it when the user types /impl, or asks to implement or start on a brief from /prep.
---

# Impl

Implement a brief that the prep skill wrote. The brief is the source
of truth: the person agreed to it before any code changed, and it holds
their corrections.

## Steps

1. Find the brief. Use the file the person named after the command.
   Otherwise use the newest brief that is not done: the `.md` file in
   `.briefs/` whose name sorts last (names start with the date and time)
   and whose Status is not "done". Say in one line which file you use. If
   there is none, say so and stop.
2. Read the whole brief before you change anything. If its Status is "has
   open questions", show those questions and wait for the answers. Run
   `git status --short`. If there are uncommitted changes outside
   `.briefs/` that the brief does not mention, ask the person before
   you start. If the brief names a commit, check whether the places it
   changes moved since then (`git log --oneline <commit>..HEAD -- <paths>`).
   If they did, tell the person before you start.
3. If this conversation also holds the /prep run that wrote the brief,
   follow the brief wherever the two differ.
4. Do the work described under Approach and Changes, and nothing else:
   leave alone everything under Out of scope, and note other problems in
   your report instead of fixing them. When a check under Proof is a new
   test, write that test first and run it to see it fail for the reason the
   brief gives, then make the change.
5. If something in the brief turns out to be wrong or impossible, stop and
   tell the person what you found. Do not improvise around it. When you
   need to know how something works, use the pages under Sources first,
   then the official documentation. Do not guess.
6. Run every Proof check meant for this session and compare each result
   with the baseline. If one fails, fix the code and run it again, at most
   three times for the same failure; then stop and explain. If the same
   failure is already in the baseline and the brief does not ask you to
   fix it, report it instead of fixing it. Never make a proof pass by
   weakening it: do not change the expected result, skip or delete tests,
   or add ignore entries (such as `.trivyignore`), unless the brief says
   so. Then read your own diff the way a strict reviewer would: every
   change follows the brief, nothing in the brief is missing, and nothing
   extra slipped in. Ask of each change: is it correct, does it make sense,
   and how do I know? Walk one example from the brief's Goal through the
   changed code, and confirm in the code or the docs that every name,
   argument and setting you used exists in the version in use.
7. Report in a few lines:
   - what changed, file by file,
   - each proof check and what it returned,
   - what is left for the person: commit, push, deploy, and the checks
     after deploy,
   - one line on what the brief got wrong or left out, or "nothing".
8. When every check for this session passed, set the brief's Status to
   "done". If the brief ends with a record note, append the done line it
   asks for, with today's date and the last line of your report in it, using
   `printf '%s\n' '<line>' >> <log>` with no quotes or backticks in the line.

## Always

- Check secrets by name only, and never open or print a value (no
  `cat .env`, `kubectl get secret -o ...`, `terraform output -json` or
  `get-secret-value`).
- Read a live system (a plan, `kubectl`, a cloud CLI, or a test or app start
  that reaches a shared service) only if the brief's Decisions say the
  person allowed it, or they allow it now. Report any check you skipped.
- Never run `git stash`, `checkout`, `restore`, `reset` or `clean`: they can
  erase the person's own work. Undo your own edits by editing the files back.
- Do not commit, push, deploy, or change a live system or Terraform state
  (such as `apply`, `helm upgrade`, `kubectl delete`, `terraform destroy`,
  `terraform state mv` or a migration) unless the person asks for it in this
  conversation, right before you run it, after seeing what will change. A
  decision in the brief is not enough. For Terraform, apply the saved plan
  the person saw: `terraform plan -out=<file>`, then `terraform apply <file>`.
