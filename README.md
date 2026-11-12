<div align="center">

# prep

**Think before you code.**

_Two agent skills for Claude Code, Kiro CLI and Pi: `/prep` writes a checked task brief, `/impl` implements it._

[![check](https://github.com/asx8678/prep/actions/workflows/check.yml/badge.svg)](https://github.com/asx8678/prep/actions/workflows/check.yml)

</div>

---

AI coding agents often start writing code before the task is clear: they
guess a name, copy an outdated pattern, or fix a bug without finding its
cause. `prep` splits every non-trivial change into two steps, preparation
first and implementation second. Both skills are plain Markdown:
[`skills/prep/SKILL.md`](skills/prep/SKILL.md) and
[`skills/impl/SKILL.md`](skills/impl/SKILL.md).

## What they do

| Skill | What it does |
| ----- | ------------ |
| **`/prep`** | Surveys the code read-only, reproduces every problem it reports, reads the official docs, compares options and asks at most three questions. Then it writes a **task brief** with a proof for every change. For a review or a diagnosis it returns a **checked report** instead. |
| **`/impl`** | Implements the newest brief, or the one you name: tests first, only the listed changes, every proof run. Reports what changed and what the brief got wrong or left out. |

## How it works

1. **You ask.** prep starts only when you type the command or ask for it by
   name.
2. **prep surveys.** Uncertain fixes are tried in a throwaway copy, never in
   your project.
3. **It reports in one message.** Answer in one line: `2 is wrong, 5B`, or
   `ok`.
4. **You approve the brief.** It is saved to `.briefs/` only after you accept
   or correct it. On request, prep keeps a record in `~/.briefs/` (later preps
   in any project may read it) and checks it for repeats: a kind of task that
   comes back can get a dedicated skill.
5. **`/impl` builds it.** It asks first when it is unclear which brief to
   use, and never commits, pushes or deploys unless you ask.

```text
you:   /prep fix the CVEs in the api service
prep:  reads the code, the scanner output and the advisories
       → one message: what it found, the options, up to 3 questions
you:   ok
prep:  checks its own plan and shows the brief
you:   ok
prep:  saves .briefs/2026-11-11-170900-fix-cves.md
you:   /impl
impl:  writes failing tests → makes the change → runs the proof → reports
```

|             | Prepare                 | Start fresh (optional) | Implement     |
| ----------- | ----------------------- | ---------------------- | ------------- |
| Claude Code | `/prep <request>`       | `/clear`               | `/impl`       |
| Kiro CLI    | `/prep <request>`       | `/clear`               | `/impl`       |
| Pi          | `/skill:prep <request>` | `/new`                 | `/skill:impl` |

## Limits

- The rules in the skills are instructions to the model, not a sandbox. Your
  tool's permissions are the lock, and the installer prints how to set them.
- Earlier versions were tested with Claude Haiku and Opus on small
  repositories. Fixing builds, end-to-end tests, flaky tests and failures
  seen only in CI is untested with a model.

## Install

Download the installer and run it. It is plain bash, so read it first.

```bash
curl -fsSL https://raw.githubusercontent.com/asx8678/prep/main/install-prep.sh -o install-prep.sh
less install-prep.sh
bash install-prep.sh
```

A small menu asks where, what and for which tools:

```text
Install, update or remove the prep and impl skills. Where?
  1) Every project on this computer   /home/you
  2) Only this repository             /home/you/your-repo
  q) Quit
> 1

The prep and impl skills are not installed in /home/you
  1) Install   for the tools you choose next
  2) Update    what is installed, to the version inside this file
  3) Remove    what this installer made; a skill file you changed is kept
  q) Quit
> 1

For which tools? A number switches one on or off; Enter alone goes on.
  1) [x] Claude Code   links in .claude/skills
  2) [x] Kiro CLI      links in .kiro/skills
  3) [x] Pi            reads .agents/skills, where the real copy always goes
  q) Quit
>
```

- **Every project** puts the skills in `~/.agents/skills/`, with links from
  `~/.claude/skills/` and `~/.kiro/skills/`.
- **Only this repository** is offered inside a git repository. It uses the
  same three folders there and writes nothing outside it. In Pi, run `/trust`
  first, because Pi loads project skills only from a trusted project.
- **Install** sets up the tools you leave switched on and ends with setup
  notes for each. Switching a tool off does not remove it; Remove does.
  **Update** refreshes only what is installed. Both keep a skill file you
  edited.
- The installer carries the skill text, so for a newer version download it
  again and choose Update.

To skip the menu, name the action: `bash install-prep.sh install --global`,
or `bash install-prep.sh install claude` for one tool in the repository.
`--help` lists every option, including the ones for Windows clones without
link support.

<details>
<summary>Other install methods</summary>

**By hand.** Copy the two folders in [`skills/`](skills) into your tool's
skills folder:

| Tool        | One project       | Every project       |
| ----------- | ----------------- | ------------------- |
| Claude Code | `.claude/skills/` | `~/.claude/skills/` |
| Kiro CLI    | `.kiro/skills/`   | `~/.kiro/skills/`   |
| Pi          | `.agents/skills/` | `~/.agents/skills/` |

```bash
git clone https://github.com/asx8678/prep
mkdir -p ~/.claude/skills ~/.kiro/skills ~/.agents/skills
cp -R prep/skills/prep prep/skills/impl ~/.claude/skills/   # Claude Code
cp -R prep/skills/prep prep/skills/impl ~/.kiro/skills/     # Kiro CLI
cp -R prep/skills/prep prep/skills/impl ~/.agents/skills/   # Pi
```

To update, pull and copy again; that overwrites the copies.

**Claude app (claude.ai).** The app takes each skill as a zip and limits its
description to 200 characters. In a clone, replace the `description:` line in
each `SKILL.md` with the one below, keeping the double quotes:

```yaml
# prep/skills/prep/SKILL.md
description: "Turn a rough request into a precise, checkable task brief before any code is written, or a checked review when nothing should change yet. Use only when the user types /prep or asks for prep by name."
# prep/skills/impl/SKILL.md
description: "Implement the newest task brief from /prep: follow it, run its proof commands, and report what it missed. Use after /prep, in the same conversation or right after /clear."
```

```bash
cd prep/skills
zip -r prep.zip prep
zip -r impl.zip impl
```

Upload each zip under Customize > Skills > **+** > Create skill > Upload a
skill; code execution must be turned on. Skills turned on there also load in
Claude Code as a second copy. This way is untested: the app has no repository
or git.

</details>

## Uninstall

Run the installer and choose **Remove**, or name it:

```bash
bash install-prep.sh remove --global   # every project
bash install-prep.sh remove            # the repository you are in
```

- It removes the skill folders and links it made, and a skill you copied in
  by hand and did not change. A skill file you edited is kept, with its
  links; delete that file and run Remove again to finish.
- Other skills and the `skills` folders themselves stay, and so do your
  briefs in `.briefs/` and your record in `~/.briefs/`.
- Delete the downloaded `install-prep.sh` yourself.
- In the Claude app, delete each skill under Customize > Skills.

## License

[MIT](LICENSE). Ideas borrowed from Anthropic's *feature-dev* plugin,
*superpowers*, GitHub's *Spec Kit*, *Kiro*, *Prompt Fixer* and
*agentic-council*.
