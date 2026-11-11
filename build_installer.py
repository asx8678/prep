"""Build install-prep.sh from skills/*/SKILL.md so the installer and the skills never drift apart.

Run:  python3 build_installer.py

shipped-versions.txt lists every version of each skill file that an installer
has written, as git blob ids. The installer replaces an existing skill file
only when it matches one of them, so a file someone edited is never
overwritten. The build adds the current versions; commit that file too.
"""
import hashlib
from pathlib import Path

HERE = Path(__file__).parent
SKILLS = ["prep", "impl"]
SHIPPED = HERE / "shipped-versions.txt"
SHIPPED_HEADER = (
    "# Every version of each skill file that install-prep.sh has written, as git blob ids.\n"
    "# build_installer.py adds the current ones. Never remove a line: the installer\n"
    "# replaces a skill file without asking only when it matches one of these.\n"
)


def skill_text(name: str) -> str:
    text = (HERE / "skills" / name / "SKILL.md").read_text(encoding="utf-8")
    return text if text.endswith("\n") else text + "\n"


def blob_id(text: str) -> str:
    """What `git hash-object` prints for a file with this text."""
    data = text.encode("utf-8")
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


def shipped_versions(texts: dict) -> list:
    lines = set()
    if SHIPPED.exists():
        for line in SHIPPED.read_text(encoding="utf-8").splitlines():
            if line.strip() and not line.startswith("#"):
                lines.add(line.strip())
    lines.update(f"{name} {blob_id(text)}" for name, text in texts.items())
    ordered = sorted(lines)
    SHIPPED.write_text(SHIPPED_HEADER + "".join(f"{l}\n" for l in ordered), encoding="utf-8")
    return ordered


def skill_block(name: str, text: str) -> str:
    mark = f"{name.upper()}_SKILL_EOF"
    assert mark not in text, f"heredoc marker appears in {name}"
    return (
        f'mkdir -p "$stage/{name}"\n'
        f"cat > \"$stage/{name}/SKILL.md\" <<'{mark}'\n"
        f"{text}{mark}\n"
        f"install_skill_file {name}\n\n"
    )


HEAD = r'''#!/usr/bin/env bash
# Installs the "prep" and "impl" skills into the current repository.
#
#   prep   turns a rough request into a checked task brief (read-only)
#   impl   implements the newest brief
#
# One real copy of each lives in .agents/skills, which Pi reads directly.
# Claude Code and Kiro CLI get links to those copies, so there is one file
# to edit. Running this again updates the skills but keeps a skill file you
# changed; the new version then waits in .git/prep-install/.
# Run it from anywhere inside the repository:  bash install-prep.sh
set -euo pipefail

if ! root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  echo "Run this inside a git repository: the skills and their briefs belong to one project." >&2
  exit 1
fi
cd "$root"
echo "Installing the prep and impl skills into: $root"
mkdir -p .briefs .agents/skills

# New versions are written here first. Git never commits this folder.
stage="$(git rev-parse --git-path prep-install)"
kept=""

# Every version of each skill file this installer has written (git blob ids).
# A file that matches one has no changes of yours, so it can be replaced.
shipped='
@SHIPPED@
'

install_skill_file() {
  local name="$1"
  local file=".agents/skills/$name/SKILL.md" new="$stage/$name/SKILL.md"
  mkdir -p ".agents/skills/$name"
  if [ -f "$file.bak" ]; then
    echo "Note: $file.bak is from an older version of this installer. Check it, then delete it."
  fi
  if [ ! -e "$file" ]; then
    mv "$new" "$file"
    echo "Installed $file"
  elif cmp -s "$file" "$new"; then
    rm -f "$new"
    echo "Up to date: $file"
  elif printf '%s\n' "$shipped" | grep -qxF "$name $(git hash-object "$file")"; then
    mv "$new" "$file"
    echo "Updated $file"
  else
    kept="$kept $file"
    echo "Kept $file: it has changes of yours, so it was not replaced."
    echo "  The new version is in $new"
    echo "  Compare:  git diff --no-index \"$file\" \"$new\""
    echo "  Take it:  cp \"$new\" \"$file\""
  fi
}

'''

TAIL = r'''# A copy may be refreshed when its SKILL.md is the same as the source, or
# unchanged since this installer made it: the marker holds its id then.
# Older installers left the marker empty; a shipped version counts too.
copy_unchanged() {
  local target="$1" name="$2" made now
  made="$(cat "$target/.installed-copy" 2>/dev/null || true)"
  now="$(git hash-object "$target/SKILL.md" 2>/dev/null)" || return 1
  [ "$now" = "$made" ] && return 0
  [ "$now" = "$(git hash-object ".agents/skills/$name/SKILL.md")" ] && return 0
  [ -z "$made" ] && printf '%s\n' "$shipped" | grep -qxF "$name $now"
}

# A link where possible. Where links are not available (for example Git Bash
# on Windows, where ln -s copies), a marked copy that every run refreshes.
# Links and folders this installer did not make are left alone, and so is a
# copy you changed.
link_skill() {
  local tool_dir="$1" name="$2"
  local target="$tool_dir/$name" mark=".installed-copy" want="../../.agents/skills/$name"
  mkdir -p "$tool_dir"
  if [ -L "$target" ]; then
    if [ "$(readlink "$target")" = "$want" ]; then
      echo "Linked $target"
    else
      echo "Skipped $target: it is a link of yours, to $(readlink "$target")"
    fi
    return 0
  fi
  # Without link support (core.symlinks=false, the default on Windows), git
  # checks out a committed link as a small file that holds its target. Replace
  # it, and tell git to ignore that local change so it is never committed.
  if [ -f "$target" ] && [ "$(cat "$target")" = "$want" ]; then
    rm -f "$target"
    git update-index --skip-worktree -- "$target" 2>/dev/null || true
    local exclude; exclude="$(git rev-parse --git-path info/exclude)"
    mkdir -p "$(dirname "$exclude")"
    grep -qxF "/$target/" "$exclude" 2>/dev/null || printf '/%s/\n' "$target" >> "$exclude"
    hidden="$hidden $target"
  fi
  if [ -e "$target" ] && [ ! -f "$target/$mark" ]; then
    echo "Skipped $target: it already exists and was not made by this installer"
    return 0
  fi
  if [ -e "$target" ] && ! copy_unchanged "$target" "$name"; then
    kept="$kept $target"
    echo "Kept $target: you changed this copy, so it was not refreshed."
    echo "  Copies are made from .agents/skills/$name/SKILL.md: make your change there,"
    echo "  then delete $target and run this again."
    return 0
  fi
  rm -rf "$target"
  if ln -s "$want" "$target" 2>/dev/null && [ -L "$target" ]; then
    echo "Linked $target"
  else
    rm -rf "$target"
    cp -R ".agents/skills/$name" "$target"
    rm -f "$target/SKILL.md.bak"
    git hash-object "$target/SKILL.md" > "$target/$mark"
    echo "Copied to $target (no links here: edit .agents/skills/$name/SKILL.md, then run this again to refresh the copy)"
  fi
}

hidden=""

for tool_dir in .claude/skills .kiro/skills; do
  for name in prep impl; do
    link_skill "$tool_dir" "$name"
  done
done

# The record of tasks is kept once per computer, in the home folder.
# The skill writes there only after you say yes at the end of a /prep.
header='<!-- One line per recorded task: date, project, type, briefed or done, text -->'
if [ -n "${HOME:-}" ] && [ -d "$HOME" ] && mkdir -p "$HOME/.briefs/tasks" "$HOME/.briefs/skills" 2>/dev/null; then
  if [ ! -e "$HOME/.briefs/log.md" ]; then
    printf '%s\n' "$header" > "$HOME/.briefs/log.md"
  fi
  echo "Record folder ready: $HOME/.briefs"
else
  echo "Could not create a .briefs folder in your home folder."
  echo "The skills still work. They just cannot keep a record of tasks."
fi

cat <<'NEXT_STEPS'

Done. The skills are in .agents/skills/prep and .agents/skills/impl.
To change one, edit its SKILL.md there; running this again keeps your edits.
Briefs go to .briefs/ in this repository.
The record of tasks lives in ~/.briefs/ and is shared by every
repository on this computer. Nothing is written there until you say yes
at the end of a /prep.

Use them
                1. Prepare          2. Start fresh   3. Implement
  Claude Code   /prep <request>     /clear           /impl
  Kiro CLI      /prep <request>     /clear           /impl
  Pi            /skill:prep ...     /new             /skill:impl

  The last sentence of every /prep tells you which way fits. When it
  stayed small, skip step 2: run /impl in the same conversation, or just
  say "go ahead". /impl uses the newest brief; put a file name after the
  command to pick another one.

  Pi            Trust the project (/trust), because Pi loads project
                skills only after that. If /skill:prep is not suggested,
                type it anyway; to have it suggested, turn on
                enableSkillCommands in /settings.
  Kiro CLI      A custom agent needs this line in its "resources":
                "skill://.kiro/skills/**/SKILL.md"

Keep /prep from changing your code
  The skill is told to write only in .briefs/ and ~/.briefs/.
  Your tool is what enforces that.

  Claude Code   Since v2.1.283 sessions start in auto mode, where a
                classifier approves actions instead of you. For /prep,
                start in Manual mode, which asks before every change, and
                start it in the repository root:
                  claude --permission-mode manual
                Approve tests, scanners and writes to the briefs folders;
                decline anything else. The record step is one shell
                command (cp and printf); approve it or answer A. To stop
                the prompts for the briefs folders, add to
                permissions.allow:
                  in .claude/settings.json     "Edit(/.briefs/**)"
                  in ~/.claude/settings.json   "Read(~/.briefs/**)",
                                               "Edit(~/.briefs/**)"
                "/.briefs/**" means .briefs in the folder the session
                starts in, so it works only from the repository root.
                For a stronger guard, use --permission-mode dontAsk: it
                refuses everything you have not allowed. So also allow
                "WebSearch", "WebFetch" and your test and scanner commands
                (for example "Bash(npm test *)"), or the brief marks those
                checks UNVERIFIED or UNTESTED. What you allow still runs
                and can write files (tests write caches and snapshots).
                dontAsk also refuses the multiple-choice questions; /prep
                then asks them as plain text. Use a normal session for /impl.
  Kiro CLI v3   It asks before writes and before commands that are not
                read-only. To stop the prompts for the briefs folders,
                add these rules to ~/.kiro/settings/permissions.yaml:
                  rules:
                    - capability: fs_read
                      match: ["~/.briefs/**"]
                      effect: allow
                    - capability: fs_write
                      match: [".briefs/**", "~/.briefs/**"]
                      effect: allow
  Pi            Pi does not ask before it acts. Run "git status" after a
                /prep. Only .briefs/ should have changed.

Commit .agents/, .claude/skills and .kiro/skills so the team gets the
skills, and the briefs in .briefs/ if the team should see them (git shows
.briefs/ only once it holds a brief). ~/.briefs/ stays on your computer.
NEXT_STEPS

if [ -n "$hidden" ]; then
  echo
  echo "This clone has no link support, so git checked out these links as small"
  echo "files:$hidden"
  echo "They are now copies, and git ignores that local change (skip-worktree and"
  echo ".git/info/exclude), so it is never committed."
fi
if [ -n "$kept" ]; then
  echo
  echo "Not updated, because they have changes of yours:$kept"
  echo "See the messages at the top."
fi
'''

texts = {n: skill_text(n) for n in SKILLS}
head = HEAD.replace("@SHIPPED@", "\n".join(shipped_versions(texts)))
body = "".join(skill_block(n, texts[n]) for n in SKILLS)
script = head + body + TAIL
out = HERE / "install-prep.sh"
out.write_text(script, encoding="utf-8")
out.chmod(0o755)
print(f"wrote {out} ({len(script.splitlines())} lines)")
