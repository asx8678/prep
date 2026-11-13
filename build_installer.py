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
# Installs, updates or removes the "prep" and "impl" skills, in one
# repository or for every project on this computer.
#
#   prep   turns a rough request into a checked task brief (read-only)
#   impl   implements the newest brief
#
# One real copy of each lives in .agents/skills, which Pi reads directly.
# Claude Code and Kiro CLI get links to those copies, so there is one file
# to edit. These folders are in the root of the repository, or with --global
# in your home folder. An update keeps a skill file you changed; the new
# version then waits in .git/prep-install/, or in ~/.agents/prep-install/.
#   bash install-prep.sh                    a menu: where, and what to do
#   bash install-prep.sh install --global   no menu; --help lists the rest
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: bash install-prep.sh [install | update | remove] [--global]
                            [claude] [kiro] [pi] [--copies | --undo-copies]

Without install, update or remove, a small menu asks where, what and, for
an install, for which tools.

  install   set up the prep and impl skills for the tools you name, or for
            all three when you name none:
              claude   Claude Code   links in .claude/skills
              kiro     Kiro CLI      links in .kiro/skills
              pi       Pi            reads .agents/skills directly
            The real copy always goes to .agents/skills, so Pi can use the
            skills whichever tools you name. Skills already there are
            updated, and a skill file you changed is kept.
  update    bring what is installed to the version inside this file, and
            set up no tool that is not set up yet. For a newer version,
            download this file again.
  remove    delete what this installer made, for all three tools. A skill
            file you changed is kept, and so are your briefs.

  --global  use your home folder, so every project on this computer has
            the skills. Without it: the git repository you are in.

Only for a clone without link support (the default on Windows), where git
checks out the committed links as small text files:
  --copies        replace those files with local copies of the skills
  --undo-copies   put those files back, and install nothing
USAGE
}

action="" scope="" tools="" copies=no undo=no
for arg in "$@"; do
  arg="$(printf '%s' "$arg" | tr '[:upper:]' '[:lower:]')"
  case "$arg" in
    install|update|remove) action="$arg" ;;
    --global) scope=home ;;
    claude|kiro|pi)
      case " $tools " in *" $arg "*) ;; *) tools="$tools $arg" ;; esac ;;
    --copies) copies=yes ;;
    --undo-copies) undo=yes ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; echo >&2; usage >&2; exit 2 ;;
  esac
done
if [ "$copies" = yes ] && [ "$undo" = yes ]; then
  echo "Use --copies or --undo-copies, not both." >&2
  exit 2
fi
named="$tools"
[ -n "$tools" ] || tools=" claude kiro pi"
has() { case " $tools " in *" $1 "*) return 0 ;; esac; return 1; }

repo="$(git rev-parse --show-toplevel 2>/dev/null)" || repo=""

# The menu reads its answers as plain lines of input, so a script can answer
# it too. Anything that is not one of the choices ends the run with nothing done.
menu=no
[ -n "$action" ] || [ "$undo" = yes ] || menu=yes
# choose N [enter]: reads an answer from 1 to N into $answer. With "enter",
# Enter alone is an answer too; the end of the input never is.
choose() {
  printf '> '
  read -r answer || answer=end
  case "$answer" in
    q|Q) echo "Nothing done."; exit 0 ;;
    [1-$1]) return 0 ;;
    "") [ -z "${2:-}" ] || return 0 ;;
  esac
  echo "Not one of the choices, so nothing was done." >&2
  exit 1
}

if [ "$menu" = yes ] && [ -z "$scope" ]; then
  if [ -n "$repo" ]; then
    cat <<WHERE
Install, update or remove the prep and impl skills. Where?
  1) Every project on this computer   $HOME
  2) Only this repository             $repo
  q) Quit
WHERE
    choose 2
    case "$answer" in 1) scope=home ;; 2) scope=repo ;; esac
    echo
  else
    # Outside a repository there is only one place.
    scope=home
  fi
fi

if [ "$scope" = home ]; then
  if [ "$copies" = yes ] || [ "$undo" = yes ]; then
    echo "--copies and --undo-copies are for a repository, not for your home folder." >&2
    exit 2
  fi
  root="$HOME"
  cd "$root"
  # Outside every skills folder: Pi loads any SKILL.md below one.
  stage="$root/.agents/prep-install"
elif [ -n "$repo" ]; then
  scope=repo
  root="$repo"
  cd "$root"
  # Git never commits this folder.
  stage="$(git rev-parse --git-path prep-install)"
  case "$stage" in /*) ;; *) stage="$root/$stage" ;; esac
else
  echo "This is not inside a git repository. Run it inside one, or add --global" >&2
  echo "to install for every project on this computer." >&2
  exit 1
fi

# Every version of each skill file this installer has written (git blob ids).
# A file that matches one has no changes of yours, so it can be replaced.
shipped='
@SHIPPED@
'
is_shipped() { printf '%s\n' "$shipped" | grep -qxF "$1 $(git hash-object "$2" 2>/dev/null)"; }

# A copy may be refreshed or removed when its SKILL.md is the same as the
# source, or unchanged since this installer made it: the marker holds its id
# then. Older installers left the marker empty; a shipped version counts too.
copy_unchanged() {
  local target="$1" name="$2" made now
  made="$(cat "$target/.installed-copy" 2>/dev/null || true)"
  now="$(git hash-object "$target/SKILL.md" 2>/dev/null)" || return 1
  [ "$now" = "$made" ] && return 0
  [ "$now" = "$(git hash-object ".agents/skills/$name/SKILL.md" 2>/dev/null)" ] && return 0
  [ -z "$made" ] && is_shipped "$name" "$target/SKILL.md"
}

# What a tool's path for a skill holds now:
#   none     nothing
#   link     our link
#   text     our link, checked out by git as a small text file
#   copy     our copy, unchanged
#   edited   our copy, with changes of yours
#   other    a link, file or folder that is not ours
# Our copy has the marker, or is a folder with nothing but a SKILL.md, which
# is what copying a skill by hand leaves.
state_of() {
  local target="$1" name="$2"
  local want="../../.agents/skills/$name"
  if [ -L "$target" ]; then
    if [ "$(readlink "$target")" = "$want" ]; then echo link; else echo other; fi
  elif [ -f "$target" ]; then
    if [ "$(cat "$target")" = "$want" ]; then echo text; else echo other; fi
  elif [ ! -e "$target" ]; then
    echo none
  elif [ ! -f "$target/.installed-copy" ] && [ "$(ls -A "$target")" != SKILL.md ]; then
    echo other
  elif copy_unchanged "$target" "$name"; then
    echo copy
  else
    echo edited
  fi
}

set_up() {
  local name
  for name in prep impl; do
    case "$(state_of ".$1/skills/$name" "$name")" in none|other) ;; *) return 0 ;; esac
  done
  return 1
}
installed() {
  [ -e .agents/skills/prep/SKILL.md ] || [ -e .agents/skills/impl/SKILL.md ] ||
    set_up claude || set_up kiro
}

# --undo-copies: put back the small text files that --copies replaced.
undo_copies() {
  local tool name target exclude restored=no
  exclude="$(git rev-parse --git-path info/exclude)"
  for tool in claude kiro; do
    has "$tool" || continue
    for name in prep impl; do
      target=".$tool/skills/$name"
      git ls-files -v -- "$target" | grep -q '^[Ss] ' || continue
      if [ -d "$target" ] && ! copy_unchanged "$target" "$name"; then
        echo "Kept $target: you changed this copy. Move your change to"
        echo "  .agents/skills/$name/SKILL.md, delete $target, and run this again."
        continue
      fi
      rm -rf "$target"
      git update-index --no-skip-worktree -- "$target"
      git checkout -q -- "$target"
      if [ -f "$exclude" ]; then
        grep -vxF "/$target/" "$exclude" > "$exclude.new" || true
        mv "$exclude.new" "$exclude"
      fi
      echo "Restored $target"
      restored=yes
    done
  done
  if [ "$restored" = yes ]; then
    echo "Git tracks these links normally again. Nothing in .agents/skills was touched."
  else
    echo "Nothing to undo: no link here is replaced by a local copy."
  fi
}

if [ "$undo" = yes ]; then
  undo_copies
  exit 0
fi

if [ "$menu" = yes ]; then
  if installed; then now="installed"; else now="not installed"; fi
  if [ -n "$named" ]; then for_tools="for:$named"; else for_tools="for the tools you choose next"; fi
  cat <<WHAT
The prep and impl skills are $now in $root
  1) Install   $for_tools
  2) Update    what is installed, to the version inside this file
  3) Remove    what this installer made; a skill file you changed is kept
  q) Quit
WHAT
  choose 3
  case "$answer" in 1) action=install ;; 2) action=update ;; 3) action=remove ;; esac
  echo
fi
if [ -n "$named" ] && [ "$action" != install ]; then
  echo "Name tools only with install: $action works on everything that is installed." >&2
  exit 2
fi

if [ "$menu" = yes ] && [ "$action" = install ] && [ -z "$named" ]; then
  box() { if has "$1"; then echo "[x]"; else echo "[ ]"; fi; }
  flip() { if has "$1"; then tools="${tools/ $1/}"; else tools="$tools $1"; fi; }
  # Only a number asks again, so this ends when the input does.
  while :; do
    cat <<TOOLS
For which tools? A number switches one on or off; Enter alone goes on.
  1) $(box claude) Claude Code   links in .claude/skills
  2) $(box kiro) Kiro CLI      links in .kiro/skills
  3) $(box pi) Pi            reads .agents/skills, where the real copy always goes
  q) Quit
TOOLS
    choose 3 enter
    case "$answer" in
      1) flip claude ;;
      2) flip kiro ;;
      3) flip pi ;;
      *) break ;;
    esac
    echo
  done
  if [ -z "$tools" ]; then
    echo "No tool is switched on, so nothing was done." >&2
    exit 1
  fi
  echo
  # The commands printed at the end name the tools that were chosen here.
  named="$tools"
fi

kept=""

# Removes one skill: the real copy, and the links and copies made from it.
# A real copy you changed stays, with its links, so that skill keeps working.
remove_skill() {
  local name="$1" tool target
  local dir=".agents/skills/$name"
  if [ -e "$dir/SKILL.md" ] && ! is_shipped "$name" "$dir/SKILL.md"; then
    kept="$kept $dir/SKILL.md"
    echo "Kept $name: $dir/SKILL.md has changes of yours."
    return 0
  fi
  for tool in claude kiro; do
    target=".$tool/skills/$name"
    case "$(state_of "$target" "$name")" in
      none) ;;
      link|text|copy) rm -rf "$target"; echo "Removed $target" ;;
      *) echo "Kept $target: it is not from this installer, or you changed it" ;;
    esac
  done
  if [ -e "$dir/SKILL.md" ]; then
    rm -f "$dir/SKILL.md"
    echo "Removed $dir/SKILL.md"
  fi
  rmdir "$dir" 2>/dev/null || [ ! -e "$dir" ] || echo "Kept $dir: it holds other files"
}

if [ "$action" = remove ]; then
  echo "Removing the prep and impl skills"
  echo "From: $root"
  # Git must see that a link is gone, so a local copy becomes the link again first.
  [ "$scope" = home ] || undo_copies > /dev/null
  for name in prep impl; do
    remove_skill "$name"
  done
  rm -rf "$stage"
  echo
  echo "Done. Your briefs in .briefs/ and your record in ~/.briefs/ were not touched."
  if [ -n "$kept" ]; then
    echo "Not removed, because they have changes of yours:$kept"
    echo "To remove one anyway, delete that file and run this again."
  fi
  exit 0
fi

if [ "$action" = update ]; then
  if ! installed; then
    echo "Nothing to update: the skills are not installed in $root"
    exit 0
  fi
  tools=" pi"
  for tool in claude kiro; do
    if set_up "$tool"; then tools="$tools $tool"; fi
  done
  echo "Updating the prep and impl skills for:$tools"
else
  echo "Installing the prep and impl skills for:$tools"
fi
echo "Into: $root"
# ~/.briefs is prep's record, which only /prep creates, and only after a yes.
[ "$scope" = home ] || mkdir -p .briefs
mkdir -p .agents/skills

# New versions are written to $stage first. The commands printed for a kept
# file have full paths, so they work from the folder you are in.
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
  elif is_shipped "$name" "$file"; then
    mv "$new" "$file"
    echo "Updated $file"
  else
    kept="$kept $file"
    echo "Kept $file: it has changes of yours, so it was not replaced."
    echo "  The new version is in $new"
    echo "  Compare:  git diff --no-index \"$root/$file\" \"$new\""
    echo "  Take it:  cp \"$new\" \"$root/$file\""
  fi
}

'''

TAIL = r'''# A link where possible. Where links are not available (for example Git Bash
# on Windows, where ln -s copies), a marked copy that every run refreshes.
# Links and folders this installer did not make are left alone, and so is a
# copy you changed.
link_skill() {
  local tool_dir="$1" name="$2"
  local target="$tool_dir/$name" mark=".installed-copy" want="../../.agents/skills/$name"
  mkdir -p "$tool_dir"
  case "$(state_of "$target" "$name")" in
    link)
      echo "Linked $target"
      return 0 ;;
    other)
      echo "Skipped $target: it already exists and was not made by this installer"
      return 0 ;;
    edited)
      kept="$kept $target"
      echo "Kept $target: you changed this copy, so it was not refreshed."
      echo "  Copies are made from .agents/skills/$name/SKILL.md: make your change there,"
      echo "  then delete $target and run this again."
      return 0 ;;
    text)
      # Without link support (core.symlinks=false, the default on Windows), git
      # checks out a committed link as a small file that holds its target. Leave
      # it alone and explain the choices at the end. Only with --copies: replace
      # it with a copy, and tell git to ignore that local change so it is never
      # committed. Git then refuses to switch to a branch without this link, so
      # this is never done unasked.
      if [ "$copies" != yes ]; then
        textlinks="$textlinks $target"
        echo "Skipped $target: git checked this link out as a small text file"
        return 0
      fi
      git update-index --skip-worktree -- "$target" 2>/dev/null || true
      local exclude; exclude="$(git rev-parse --git-path info/exclude)"
      mkdir -p "$(dirname "$exclude")"
      grep -qxF "/$target/" "$exclude" 2>/dev/null || printf '/%s/\n' "$target" >> "$exclude"
      hidden="$hidden $target" ;;
  esac
  rm -rf "$target"
  # The link must also open: it does not when the tool folder is itself a
  # link to a folder somewhere else.
  if ln -s "$want" "$target" 2>/dev/null && [ -L "$target" ] && [ -e "$target/SKILL.md" ]; then
    echo "Linked $target"
  else
    rm -rf "$target"
    cp -R ".agents/skills/$name" "$target"
    rm -f "$target/SKILL.md.bak"
    git hash-object "$target/SKILL.md" > "$target/$mark"
    echo "Copied to $target (a link does not work here: edit .agents/skills/$name/SKILL.md, then run this again to refresh the copy)"
  fi
}

hidden="" textlinks=""

for tool in claude kiro; do
  if ! has "$tool"; then
    if set_up "$tool"; then
      echo "Left as it is: .$tool/skills was set up before. Leaving a tool out does not remove it."
    fi
    continue
  fi
  for name in prep impl; do
    link_skill ".$tool/skills" "$name"
  done
done
# Only a new version that is waiting for you stays in $stage.
rmdir "$stage/prep" "$stage/impl" "$stage" 2>/dev/null || true

# What to do next, only for the tools that were set up.
notes() {
cat <<DONE

Done. The skills are in $root/.agents/skills
(prep and impl). To change one, edit its SKILL.md there; running this
again keeps your edits.
Briefs go to .briefs/ in the project you run /prep in. /prep puts a
.gitignore there, so git leaves them out until you delete that file.
The record of tasks lives in ~/.briefs/ and is shared by every
repository on this computer. Nothing is written there until you say
"keep a record" at the end of a /prep. From then on it gets a log line
and a copy of every brief you save, unless you say "no record".

Use them
                1. Prepare          2. Start fresh   3. Implement
DONE
if has claude; then echo "  Claude Code   /prep <request>     /clear           /impl"; fi
if has kiro; then echo "  Kiro CLI      /prep <request>     /clear           /impl"; fi
if has pi; then echo "  Pi            /skill:prep ...     /new             /skill:impl"; fi
cat <<'FRESH'

  The last sentence of every /prep tells you which way fits. When it
  stayed small, skip step 2: run /impl in the same conversation, or just
  say "go ahead". /impl uses the newest brief; put a file name after the
  command to pick another one.
FRESH
if has pi || has kiro; then echo; fi
if has pi && [ "$scope" = repo ]; then cat <<'PI_TRUST'
  Pi            Trust the project (/trust), because Pi loads project
                skills only after that.
PI_TRUST
fi
if has pi; then cat <<'PI_USE'
  Pi            If /skill:prep is not suggested, type it anyway; to have
                it suggested, turn on enableSkillCommands in /settings.
PI_USE
fi
if has kiro; then
  if [ "$scope" = repo ]; then kiro_skills='skill://.kiro/skills/**/SKILL.md'
  else kiro_skills='skill://~/.kiro/skills/*/SKILL.md'; fi
  cat <<KIRO_USE
  Kiro CLI      A custom agent needs this line in its "resources":
                "$kiro_skills"
KIRO_USE
fi
cat <<'GUARD'

Keep /prep from changing your code
  The skill is told to write only in .briefs/ and ~/.briefs/.
  Your tool is what enforces that.

GUARD
if has claude; then cat <<'CLAUDE_GUARD'
  Claude Code   Since v2.1.283 sessions start in auto mode, where a
                classifier approves actions instead of you. For /prep,
                start in Manual mode, which asks before every change, and
                start it in the repository root:
                  claude --permission-mode manual
                Approve tests, scanners and writes to the briefs folders;
                decline anything else. The record step is one shell
                command (cp and printf); approve it, or say "no record"
                when you accept the brief. To stop the prompts for the
                briefs folders, add to permissions.allow:
                  in the project's .claude/settings.json
                    "Edit(/.briefs/**)"
                  in ~/.claude/settings.json
                    "Read(~/.briefs/**)", "Edit(~/.briefs/**)"
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
CLAUDE_GUARD
fi
if has kiro; then cat <<'KIRO_GUARD'
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
KIRO_GUARD
fi
if has pi; then cat <<'PI_GUARD'
  Pi            Pi does not ask before it acts. Run "git status" after a
                /prep. Only .briefs/ should have changed.
PI_GUARD
fi
if [ "$scope" = repo ]; then
  folders=".agents/"
  if has claude; then folders="$folders, .claude/skills"; fi
  if has kiro; then folders="$folders, .kiro/skills"; fi
  case "$folders" in *", "*) folders="${folders%, *} and ${folders##*, }" ;; esac
  cat <<COMMIT

Commit $folders so the team gets the
skills. Briefs stay out of commits, because /prep puts a .gitignore into
.briefs/; delete that file if the team should see them. ~/.briefs/ stays
on your computer.
COMMIT
fi
}

if [ "$action" = install ]; then
  notes
else
  echo
  echo "That is the version inside this file. For a newer one, download the file again."
fi

if [ -n "$textlinks" ]; then
  cat <<TEXTLINKS

This clone has no link support, so git checked out these links as small text
files, and the skills cannot be loaded through them:
 $textlinks
Pi is not affected: it reads .agents/skills directly. Choose one:

  1. Turn on link support (the clean way). On Windows, turn on Developer
     Mode first. Then, in this repository:
       git config core.symlinks true
       rm$textlinks
       git checkout --$textlinks
     and run this installer again.

  2. Use local copies instead:
       bash install-prep.sh install$named --copies
     Git then refuses to switch to a branch that does not have these links,
     and to pull a change to them, until you run:
       bash install-prep.sh$named --undo-copies
TEXTLINKS
fi
if [ -n "$hidden" ]; then
  cat <<HIDDEN

These links are now local copies, and git ignores that local change
(skip-worktree and .git/info/exclude), so it is never committed:
 $hidden
Until you undo this, git refuses to switch to a branch that does not have
these links, and to pull a change to them. To undo:
  bash install-prep.sh$named --undo-copies
HIDDEN
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
