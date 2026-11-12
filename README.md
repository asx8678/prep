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

Run the installer inside the git repository where you want the skills. It is
plain bash, so read it first.

```bash
cd your-repo
curl -fsSL https://raw.githubusercontent.com/asx8678/prep/main/install-prep.sh -o install-prep.sh
less install-prep.sh
bash install-prep.sh
```

It sets up Claude Code, Kiro CLI and Pi, or only the tools you name
(`bash install-prep.sh claude`). The skills go to `.agents/skills/`, with
links from `.claude/skills/` and `.kiro/skills/`, and nothing is written
outside the repository. To update, download and run it again: a skill file
you edited is kept. It ends with setup notes for each tool, and `--help`
lists every option, including the ones for Windows clones without link
support. In Pi, run `/trust` first, because Pi loads project skills only from
a trusted project.

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

There is no uninstall step. In the repository, remove the six paths the
installer made:

```bash
rm -rf .agents/skills/prep .agents/skills/impl \
       .claude/skills/prep .claude/skills/impl \
       .kiro/skills/prep .kiro/skills/impl
```

- If you used `--copies`, run `bash install-prep.sh --undo-copies` first, or
  git will not see that the links are gone.
- That leaves the downloaded `install-prep.sh`, `.git/prep-install/` (a new
  version the installer kept next to an edit of yours, or nothing) and the
  now empty `.agents/skills`, `.claude/skills` and `.kiro/skills`. Delete
  them too if nothing else uses them.
- Copied by hand? Delete `prep` and `impl` from `~/.claude/skills/`,
  `~/.kiro/skills/` and `~/.agents/skills/`.
- In the Claude app, delete each skill under Customize > Skills.
- Your briefs in `.briefs/` and your record in `~/.briefs/` stay until you
  delete them.

## License

[MIT](LICENSE). Ideas borrowed from Anthropic's *feature-dev* plugin,
*superpowers*, GitHub's *Spec Kit*, *Kiro*, *Prompt Fixer* and
*agentic-council*.
