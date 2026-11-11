"""Build install-prep.sh from skills/*/SKILL.md so the installer and the skills never drift apart.

Run:  python3 build_installer.py
"""
from pathlib import Path

HERE = Path(__file__).parent
SKILLS = ["prep", "impl"]


def skill_block(name: str) -> str:
    text = (HERE / "skills" / name / "SKILL.md").read_text(encoding="utf-8")
    if not text.endswith("\n"):
        text += "\n"
    mark = f"{name.upper()}_SKILL_EOF"
    assert mark not in text, f"heredoc marker appears in {name}"
    return (
        f'mkdir -p ".agents/skills/{name}"\n'
        f"cat > \".agents/skills/{name}/SKILL.md.new\" <<'{mark}'\n"
        f"{text}{mark}\n"
        f'install_skill_file ".agents/skills/{name}"\n\n'
    )


HEAD = r'''#!/usr/bin/env bash
# Installs the "prep" and "impl" skills into the current repository.
#
#   prep   turns a rough request into a checked task brief (read-only)
#   impl   implements the newest brief
#
# One real copy of each lives in .agents/skills, which Pi reads directly.
# Claude Code and Kiro CLI get links to those copies, so there is one file to edit.
# Run it from anywhere inside the repository:  bash install-prep.sh
set -euo pipefail

if ! root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  echo "Run this inside a git repository: the skills and their briefs belong to one project." >&2
  exit 1
fi
cd "$root"
echo "Installing the prep and impl skills into: $root"
mkdir -p .briefs

# Keep a backup only when an existing skill file differs from the new one.
install_skill_file() {
  local dir="$1"
  if [ -f "$dir/SKILL.md" ] && ! cmp -s "$dir/SKILL.md" "$dir/SKILL.md.new"; then
    cp "$dir/SKILL.md" "$dir/SKILL.md.bak"
    echo "Your previous $dir/SKILL.md was different. Kept it as $dir/SKILL.md.bak"
  fi
  mv "$dir/SKILL.md.new" "$dir/SKILL.md"
}

'''

TAIL = r'''# A link where possible. Where links are not available (for example Git Bash
# on Windows, where ln -s copies), a marked copy that every run refreshes.
link_skill() {
  local tool_dir="$1" name="$2"
  local target="$tool_dir/$name" mark=".installed-copy"
  mkdir -p "$tool_dir"
  if [ -e "$target" ] && [ ! -L "$target" ] && [ ! -f "$target/$mark" ]; then
    echo "Skipped $target: it already exists and was not made by this installer"
    return 0
  fi
  rm -rf "$target"
  ln -s "../../.agents/skills/$name" "$target" 2>/dev/null || true
  if [ -L "$target" ]; then
    echo "Linked $target"
  else
    rm -rf "$target"
    cp -R ".agents/skills/$name" "$target"
    rm -f "$target/SKILL.md.bak"
    : > "$target/$mark"
    echo "Copied to $target (links are not available here; run this again after editing the skills)"
  fi
}

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
                skills only after that. If /skill:prep does not
                appear, turn on skill commands in /settings
                (enableSkillCommands).
  Kiro CLI      A custom agent needs this line in its "resources":
                "skill://.kiro/skills/**/SKILL.md"

Keep /prep from changing your code
  The skill is told to write only in .briefs/ and ~/.briefs/.
  Your tool is what enforces that.

  Claude Code   Since v2.1.283 sessions start in auto mode, where a
                classifier approves actions instead of you. For /prep,
                start in Manual mode, which asks before every change:
                  claude --permission-mode manual
                Approve tests, scanners and writes to the briefs folders;
                decline anything else. The record step is one shell
                command (cp and printf); approve it or answer A. To stop
                the prompts for the briefs folders, add to
                permissions.allow:
                  in .claude/settings.json     "Edit(/.briefs/**)"
                  in ~/.claude/settings.json   "Read(~/.briefs/**)",
                                               "Edit(~/.briefs/**)"
                For a hard guarantee, use --permission-mode dontAsk: it
                refuses everything not allowed, so also allow "WebSearch",
                "WebFetch" and your test and scanner commands (for example
                "Bash(npm test *)"), or the brief marks those checks
                UNVERIFIED or UNTESTED. Use a normal session for /impl.
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

Commit .agents/, .claude/skills, .kiro/skills and .briefs/ so the team
gets the skills and the briefs. ~/.briefs/ stays on your computer.
NEXT_STEPS
'''

body = "".join(skill_block(n) for n in SKILLS)
script = HEAD + body + TAIL
out = HERE / "install-prep.sh"
out.write_text(script, encoding="utf-8")
out.chmod(0o755)
print(f"wrote {out} ({len(script.splitlines())} lines)")
