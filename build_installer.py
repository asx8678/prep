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

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
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

TAIL = r'''link_skill() {
  local tool_dir="$1" name="$2"
  local target="$tool_dir/$name"
  mkdir -p "$tool_dir"
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    echo "Skipped $target: it already exists and is not a link"
    return 0
  fi
  if ln -sfn "../../.agents/skills/$name" "$target" 2>/dev/null; then
    echo "Linked $target"
  else
    rm -rf "$target"
    cp -R ".agents/skills/$name" "$target"
    echo "Copied to $target (links are not available here)"
  fi
}

for tool_dir in .claude/skills .kiro/skills; do
  for name in prep impl; do
    link_skill "$tool_dir" "$name"
  done
done

# The record of tasks is kept once per computer, in the home folder.
# The skill writes there only after you say yes at the end of a /prep.
header='<!-- One line per recorded task: date | project | type | briefed / done | text -->'
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

  Claude Code   In the normal mode it asks before every file change and
                before every command that is not read-only. Approve test
                and scanner runs and writes to the briefs folders, and
                decline anything else. To stop the prompts for those
                folders, add to permissions.allow:
                  in .claude/settings.json     "Edit(/.briefs/**)"
                  in ~/.claude/settings.json   "Read(~/.briefs/**)",
                                               "Edit(~/.briefs/**)"
                For a hard guarantee, start the session with:
                  claude --permission-mode dontAsk
                It then refuses everything that is not allowed. That
                includes test and scanner commands, so the brief marks
                the proof UNTESTED unless you allow them too, for
                example "Bash(npm test *)". For /impl, start a normal
                session instead, because it has to edit files.
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
