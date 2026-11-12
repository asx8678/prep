#!/usr/bin/env bash
# Checks the installer and the commands inside the skills.
#
#   bash tests/run.sh
#
# Each check looks at what was done (files, links, exit codes, git state), not
# at the wording of a message. Everything happens in one temporary folder:
# HOME, the git config and every repository are in it, so nothing in this
# repository or in your home folder changes. The upgrade checks read older
# versions of the skills from this repository's history, so they need a full
# clone.
set -u

repo="$(cd "$(dirname "$0")/.." && pwd -P)"
installer="$repo/install-prep.sh"
shell="${BASH:-bash}"
links_to="../../.agents/skills"
# prep is already larger than the 5,000 tokens a skill should have, so a new
# rule has to replace an old one. Raise this number only on purpose.
max_prep_bytes=28639

work="$(mktemp -d)" || exit 1
work="$(cd "$work" && pwd -P)"
trap 'rm -rf "$work"' EXIT

real_path="$PATH"
real_mktemp="$(command -v mktemp)"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
export HOME="$work/home"
export GIT_CONFIG_GLOBAL="$work/gitconfig" GIT_CONFIG_NOSYSTEM=1
# Git must never find a repository above the temporary folder.
export GIT_CEILING_DIRECTORIES="$work"
mkdir -p "$HOME" "$work/mk"
git config --global user.name "Test"
git config --global user.email "test@example.invalid"
git config --global init.defaultBranch main
git config --global commit.gpgsign false
git config --global safe.directory '*'

pass=0 fail=0
ok() { pass=$((pass + 1)); printf 'ok    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL  %s\n' "$1"; }

# expect NAME COMMAND...   passes when the command succeeds
expect() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi; }
# refuse NAME COMMAND...   passes when the command fails
refuse() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then bad "$name"; else ok "$name"; fi; }
# same NAME GOT WANT
same() {
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1"; printf '      got:  %s\n      want: %s\n' "$2" "$3"; fi
}

is_link_to() { [ -L "$1" ] && [ "$(readlink "$1")" = "$2" ]; }
is_text_link() { [ -f "$1" ] && [ ! -L "$1" ] && [ "$(cat "$1")" = "$2" ]; }
is_copy() { [ -d "$1" ] && [ ! -L "$1" ] && [ -f "$1/.installed-copy" ]; }
is_empty_dir() { [ -d "$1" ] && [ -z "$(ls -A "$1")" ]; }
is_skill() { cmp -s "$1" "$repo/skills/$2/SKILL.md"; }
in_range() { [ "$1" -ge "$2" ] && [ "$1" -le "$3" ]; }
contains() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }
is_stamp() {
  case "$1" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]) return 0 ;;
  esac
  return 1
}

# Every file and link below a folder, with its content, as one text.
tree() {
  ( cd "$1" && find . -path ./.git -prune -o \( -type f -o -type l \) -print | LC_ALL=C sort |
    while IFS= read -r f; do
      if [ -L "$f" ]; then printf 'link %s -> %s\n' "$f" "$(readlink "$f")"
      else printf 'file %s %s\n' "$f" "$(cksum < "$f")"; fi
    done )
}

repos=0
# new_repo: sets $r to a new repository with one commit
new_repo() {
  repos=$((repos + 1))
  r="$work/repo$repos"
  mkdir -p "$r" && git -C "$r" init -q && printf 'one\n' > "$r/a.txt" &&
    git -C "$r" add a.txt && git -C "$r" commit -q -m first
}

fake_bin=""
# run DIR [ARGS...]: runs the installer in DIR; sets $rc, keeps the output in $work/out
run() {
  local dir="$1"; shift
  ( cd "$dir" && PATH="${fake_bin:+$fake_bin:}$real_path" "$shell" "$installer" "$@" ) > "$work/out" 2>&1
  rc=$?
}

# old_version NAME FILE: writes an older shipped version of a skill to FILE
old_version() {
  local name="$1" out="$2" who id now
  now="$(git hash-object "$repo/skills/$name/SKILL.md")"
  while read -r who id; do
    [ "$who" = "$name" ] && [ "$id" != "$now" ] || continue
    git -C "$repo" cat-file -p "$id" > "$out" 2>/dev/null && [ -s "$out" ] && return 0
  done < "$repo/shipped-versions.txt"
  return 1
}
no_history="an older version can be read from git history (a shallow clone? run: git fetch --unshallow)"

add_rule() { printf '\nmy own rule\n' >> "$1"; }

# code_block PATTERN: the fenced block in prep's text whose first line matches
code_block() {
  awk -v want="$1" '
    /^```/ { inb = !inb; if (inb) buf = ""; else if (buf ~ want) printf "%s", buf; next }
    inb { buf = buf $0 "\n" }' "$repo/skills/prep/SKILL.md"
}

echo "== 1. The installer is what build_installer.py builds from skills/"
b="$work/build"
mkdir -p "$b" && cp "$repo/build_installer.py" "$repo/install-prep.sh" "$repo/shipped-versions.txt" "$b/" &&
  cp -R "$repo/skills" "$b/skills"
( cd "$b" && python3 build_installer.py ) > "$work/out" 2>&1
same "1 the build runs" "$?" 0
expect "1 install-prep.sh is what the build produces (if not: python3 build_installer.py)" cmp -s "$b/install-prep.sh" "$installer"
expect "1 shipped-versions.txt is what the build produces" cmp -s "$b/shipped-versions.txt" "$repo/shipped-versions.txt"

echo "== 2. The skill files"
for name in prep impl; do
  f="$repo/skills/$name/SKILL.md"
  same "2 $name: the name in the frontmatter is the folder name" "$(sed -n '2,/^---$/s/^name: *//p' "$f")" "$name"
  d="$(sed -n '2,/^---$/s/^description: *//p' "$f")"
  expect "2 $name: the description has 1 to 1,024 characters" in_range "${#d}" 1 1024
done
expect "2 prep is at most $max_prep_bytes bytes" in_range "$(($(wc -c < "$repo/skills/prep/SKILL.md")))" 1 "$max_prep_bytes"

echo "== 3. Not a git repository"
mkdir "$work/nogit"
run "$work/nogit"
same "3 exit 1" "$rc" 1
expect "3 nothing is written" is_empty_dir "$work/nogit"

echo "== 4. A fresh install"
new_repo; a="$r"
run "$a"
same "4 exit 0" "$rc" 0
for name in prep impl; do
  expect "4 .agents/skills/$name/SKILL.md is the skill" is_skill "$a/.agents/skills/$name/SKILL.md" "$name"
  for tool in claude kiro; do
    expect "4 .$tool/skills/$name links to $links_to/$name" is_link_to "$a/.$tool/skills/$name" "$links_to/$name"
    expect "4 .$tool/skills/$name/SKILL.md opens" is_skill "$a/.$tool/skills/$name/SKILL.md" "$name"
  done
done
expect "4 .briefs/ exists" test -d "$a/.briefs"
expect "4 nothing is written to HOME" is_empty_dir "$HOME"
new_repo; sub="$r"
mkdir -p "$sub/deep/down"
run "$sub/deep/down"
expect "4 from a subfolder: the skills go to the root" is_skill "$sub/.agents/skills/prep/SKILL.md" prep
refuse "4 from a subfolder: nothing is put in the subfolder" test -e "$sub/deep/down/.agents"

echo "== 5. A second run"
before="$(tree "$a")"
run "$a"
same "5 exit 0" "$rc" 0
expect "5 nothing changes" test "$(tree "$a")" = "$before"

echo "== 6. An upgrade"
new_repo; up="$r"
run "$up"
if old_version prep "$up/.agents/skills/prep/SKILL.md"; then
  refuse "6 (setup) the older version differs from today's" is_skill "$up/.agents/skills/prep/SKILL.md" prep
  run "$up"
  same "6 exit 0" "$rc" 0
  expect "6 an older shipped version is replaced" is_skill "$up/.agents/skills/prep/SKILL.md" prep
  refuse "6 no new version is left waiting" test -e "$up/.git/prep-install/prep/SKILL.md"
else
  bad "6 $no_history"
fi

echo "== 7. Your edit"
new_repo; ed="$r"
run "$ed"
add_rule "$ed/.agents/skills/prep/SKILL.md"
sum="$(cksum < "$ed/.agents/skills/prep/SKILL.md")"
run "$ed"
same "7 exit 0" "$rc" 0
same "7 an edited skill file is kept" "$(cksum < "$ed/.agents/skills/prep/SKILL.md")" "$sum"
expect "7 the new version waits in .git/prep-install/" is_skill "$ed/.git/prep-install/prep/SKILL.md" prep
expect "7 the other skill stays up to date" is_skill "$ed/.agents/skills/impl/SKILL.md" impl

echo "== 8. The choice of tools, and wrong arguments"
new_repo; t="$r"
run "$t" claude
expect "8 claude: .claude/skills/prep is linked" is_link_to "$t/.claude/skills/prep" "$links_to/prep"
refuse "8 claude: no .kiro folder" test -e "$t/.kiro"
expect "8 claude: the real copy is in .agents/skills" is_skill "$t/.agents/skills/impl/SKILL.md" impl
new_repo; t="$r"
run "$t" kiro pi
expect "8 kiro pi: .kiro/skills/impl is linked" is_link_to "$t/.kiro/skills/impl" "$links_to/impl"
refuse "8 kiro pi: no .claude folder" test -e "$t/.claude"
new_repo; t="$r"
run "$t" CLAUDE
expect "8 CLAUDE in upper case is accepted" is_link_to "$t/.claude/skills/prep" "$links_to/prep"
new_repo; t="$r"
clean="$(tree "$t")"
for args in "codex" "--bogus" "--copies --undo-copies"; do
  # $args is not quoted on purpose: each word is one argument.
  run "$t" $args
  same "8 '$args': exit 2" "$rc" 2
  expect "8 '$args': nothing is written" test "$(tree "$t")" = "$clean"
done
run "$t" --help
same "8 --help: exit 0" "$rc" 0
expect "8 --help: prints the usage" test -s "$work/out"
expect "8 --help: nothing is written" test "$(tree "$t")" = "$clean"

echo "== 9. Your own link and your own folder"
new_repo; own="$r"
mkdir -p "$own/.claude/skills" "$own/mine" "$own/.kiro/skills/impl"
ln -s ../../mine "$own/.claude/skills/prep"
printf 'mine\n' > "$own/.kiro/skills/impl/note.txt"
run "$own"
same "9 exit 0" "$rc" 0
expect "9 your own link is left alone" is_link_to "$own/.claude/skills/prep" ../../mine
expect "9 your own folder is left alone" test -f "$own/.kiro/skills/impl/note.txt"
refuse "9 your own folder gets no skill file" test -e "$own/.kiro/skills/impl/SKILL.md"
expect "9 the other links are still made" is_link_to "$own/.claude/skills/impl" "$links_to/impl"

echo "== 10. No link support"
mkdir -p "$work/ln-fails" "$work/ln-copies"
printf '#!/bin/sh\nexit 1\n' > "$work/ln-fails/ln"
cat > "$work/ln-copies/ln" <<'LN'
#!/bin/sh
# Like ln in Git Bash without link support: "ln -s TARGET NAME" copies TARGET.
[ "$1" = "-s" ] || exit 1
cp -R "$(dirname "$3")/$2" "$3"
LN
chmod +x "$work/ln-fails/ln" "$work/ln-copies/ln"
for kind in ln-fails ln-copies; do
  fake_bin="$work/$kind"
  new_repo; c="$r"
  run "$c"
  same "10 $kind: exit 0" "$rc" 0
  for tool in claude kiro; do
    for name in prep impl; do
      expect "10 $kind: .$tool/skills/$name is a marked copy" is_copy "$c/.$tool/skills/$name"
      expect "10 $kind: .$tool/skills/$name/SKILL.md is the skill" is_skill "$c/.$tool/skills/$name/SKILL.md" "$name"
    done
  done
  same "10 $kind: the mark holds the id of the copy" "$(cat "$c/.claude/skills/prep/.installed-copy")" \
    "$(cd "$c" && git hash-object .claude/skills/prep/SKILL.md)"
  add_rule "$c/.claude/skills/prep/SKILL.md"
  sum="$(cksum < "$c/.claude/skills/prep/SKILL.md")"
  : > "$c/.kiro/skills/prep/.installed-copy"
  if old_version prep "$c/.kiro/skills/prep/SKILL.md"; then
    run "$c"
    same "10 $kind: an edited copy is kept" "$(cksum < "$c/.claude/skills/prep/SKILL.md")" "$sum"
    expect "10 $kind: a copy from an older installer is refreshed" is_skill "$c/.kiro/skills/prep/SKILL.md" prep
  else
    bad "10 $kind: $no_history"
  fi
done
fake_bin=""

echo "== 11. A skills folder that is a link to somewhere else"
new_repo; lk="$r"
mkdir -p "$work/elsewhere" "$lk/.claude"
ln -s "$work/elsewhere" "$lk/.claude/skills"
run "$lk"
same "11 exit 0" "$rc" 0
expect "11 the skill opens through the linked folder" is_skill "$lk/.claude/skills/prep/SKILL.md" prep
expect "11 it is a marked copy, because a link would not open" is_copy "$work/elsewhere/prep"
expect "11 the other tool still gets links" is_link_to "$lk/.kiro/skills/prep" "$links_to/prep"

echo "== 12. A git worktree"
new_repo; main="$r"
wt="$work/worktree"
git -C "$main" worktree add -q "$wt" -b side
run "$wt"
same "12 exit 0" "$rc" 0
expect "12 the skills are installed in the worktree" is_skill "$wt/.agents/skills/prep/SKILL.md" prep
refuse "12 nothing is put in the main folder" test -e "$main/.agents"
add_rule "$wt/.agents/skills/prep/SKILL.md"
run "$wt"
stage="$(cd "$wt" && git rev-parse --git-path prep-install)"
case "$stage" in /*) ;; *) stage="$wt/$stage" ;; esac
expect "12 the kept new version is in the worktree's git folder" is_skill "$stage/prep/SKILL.md" prep
refuse "12 that git folder is not inside the worktree" test -d "$wt/.git"

echo "== 13. Windows line endings"
new_repo; crlf="$r"
run "$crlf"
git -C "$crlf" config core.autocrlf true
f="$crlf/.agents/skills/prep/SKILL.md"
awk '{ printf "%s\r\n", $0 }' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
refuse "13 (setup) the installed file now has Windows line endings" is_skill "$f" prep
run "$crlf"
same "13 exit 0" "$rc" 0
expect "13 with core.autocrlf=true the file is updated" is_skill "$f" prep
refuse "13 and it is not kept as an edit of yours" test -e "$crlf/.git/prep-install/prep/SKILL.md"

echo "== 14. A clone without link support (the default on Windows)"
new_repo; win="$r"
run "$win"
git -C "$win" add -A . && git -C "$win" commit -q -m "add the skills"
git -C "$win" config core.symlinks false
rm "$win/.claude/skills/prep" "$win/.claude/skills/impl" "$win/.kiro/skills/prep" "$win/.kiro/skills/impl"
git -C "$win" checkout -q -- .claude .kiro
fake_bin="$work/ln-copies"
expect "14 (setup) git checks a link out as a small text file" is_text_link "$win/.claude/skills/prep" "$links_to/prep"
run "$win"
same "14 exit 0" "$rc" 0
for tool in claude kiro; do
  for name in prep impl; do
    expect "14 .$tool/skills/$name: the text file is left alone" is_text_link "$win/.$tool/skills/$name" "$links_to/$name"
  done
done
same "14 git status stays clean" "$(git -C "$win" status --short)" ""
run "$win" --copies
same "14 --copies: exit 0" "$rc" 0
expect "14 --copies: a marked copy replaces the text file" is_copy "$win/.claude/skills/prep"
expect "14 --copies: the copy is the skill" is_skill "$win/.claude/skills/prep/SKILL.md" prep
same "14 --copies: git status stays clean" "$(git -C "$win" status --short)" ""
add_rule "$win/.kiro/skills/impl/SKILL.md"
run "$win" --undo-copies
same "14 --undo-copies: exit 0" "$rc" 0
expect "14 --undo-copies: the text file is back" is_text_link "$win/.claude/skills/prep" "$links_to/prep"
expect "14 --undo-copies: an edited copy is kept" is_copy "$win/.kiro/skills/impl"
same "14 --undo-copies: git status stays clean" "$(git -C "$win" status --short)" ""
fake_bin=""

echo "== 15. prep's throwaway copy (the command in the skill text)"
code_block "git clone -q" > "$work/copy.sh"
expect "15 the command is in prep's text" test -s "$work/copy.sh"
mkdir -p "$work/mkbin"
printf '#!/bin/sh\nexec "%s" -d "%s/tmp.XXXXXX"\n' "$real_mktemp" "$work/mk" > "$work/mkbin/mktemp"
chmod +x "$work/mkbin/mktemp"
# try DIR: runs the command in DIR; sets $rc and $copy (the folder it prints)
try() {
  copy="$(cd "$1" && PATH="$work/mkbin:$real_path" "$shell" "$work/copy.sh" 2> "$work/out")"
  rc=$?
}
new_repo; pr="$r"
printf '.env\n' > "$pr/.gitignore"
printf '\000\001' > "$pr/bin.dat"
git -C "$pr" add .gitignore bin.dat && git -C "$pr" commit -q -m more
printf 'two\n' > "$pr/a.txt"
printf '\000\002\003' > "$pr/bin.dat"
printf 'new\n' > "$pr/untracked.txt"
printf 'SECRET=1\n' > "$pr/.env"
before="$(tree "$pr")"
try "$pr"
same "15 exit 0" "$rc" 0
expect "15 it prints the folder of the copy" test -d "$copy/.git"
same "15 the copy holds an uncommitted change" "$(cat "$copy/a.txt" 2>/dev/null)" two
expect "15 the copy holds an uncommitted change to a binary file" cmp -s "$copy/bin.dat" "$pr/bin.dat"
refuse "15 the copy has no untracked file" test -e "$copy/untracked.txt"
refuse "15 the copy has no ignored file" test -e "$copy/.env"
same "15 the copy has no remote, so nothing can be pushed back" "$(git -C "$copy" remote 2>&1)" ""
expect "15 the project is unchanged" test "$(tree "$pr")" = "$before"
git -C "$pr" config diff.noprefix true
git -C "$pr" config color.ui always
git -C "$pr" config diff.external false
try "$pr"
same "15 with diff.noprefix, diff.external and color.ui=always: exit 0" "$rc" 0
same "15 with those settings: the copy holds the uncommitted change" "$(cat "$copy/a.txt" 2>/dev/null)" two
new_repo; plain="$r"
try "$plain"
same "15 a project with no changes: exit 0" "$rc" 0
same "15 a project with no changes: the copy holds the committed file" "$(cat "$copy/a.txt" 2>/dev/null)" one
mkdir "$work/nocommits" && git -C "$work/nocommits" init -q
rm -rf "$work/mk" && mkdir "$work/mk"
try "$work/nocommits"
refuse "15 a project with no commits: the command fails" test "$rc" -eq 0
expect "15 a project with no commits: it removes its own folder" is_empty_dir "$work/mk"

echo "== 16. prep's before-and-after command (in the skill text)"
grep -o '`git status --short; {[^`]*`' "$repo/skills/prep/SKILL.md" | tr -d '`' > "$work/state.sh"
expect "16 the command is in prep's text" test -s "$work/state.sh"
state() { ( cd "$1" && "$shell" "$work/state.sh" 2>&1 ); }
new_repo; st="$r"
printf 'cache/\n' > "$st/.gitignore"
git -C "$st" add .gitignore && git -C "$st" commit -q -m ignore
s0="$(state "$st")"
printf 'changed\n' > "$st/a.txt"; s1="$(state "$st")"
printf 'new\n' > "$st/new.txt"; s2="$(state "$st")"
mkdir "$st/cache" && printf 'x\n' > "$st/cache/x"; s3="$(state "$st")"
same "16 the same state gives the same output" "$(state "$st")" "$s3"
refuse "16 a changed file changes the output" test "$s1" = "$s0"
refuse "16 a new untracked file changes the output" test "$s2" = "$s1"
expect "16 an ignored file does not" test "$s3" = "$s2"

echo "== 17. prep's step 1 command (in the skill text)"
code_block "^date " > "$work/start.sh"
expect "17 the command is in prep's text" test -s "$work/start.sh"
start() { ( cd "$st" && "$shell" "$work/start.sh" 2>/dev/null ); }
first="$(start)"
same "17 exit 0 when ~/.briefs does not exist" "$?" 0
sleep 1
second="$(start | sed -n 1p)"
expect "17 the first line is a date and time like 2026-11-12-023300" is_stamp "$(printf '%s\n' "$first" | sed -n 1p)"
same "17 the second line is the home folder" "$(printf '%s\n' "$first" | sed -n 2p)" "$HOME"
same "17 a later run sorts after an earlier one" \
  "$(printf '%s\n%s\n' "$second" "$(printf '%s\n' "$first" | sed -n 1p)" | LC_ALL=C sort -u | tail -n 1)" "$second"

echo "== 18. prep's command for an environment variable (in the skill text)"
cmd="$(grep -o '`echo "\${NAME:+[^`]*`' "$repo/skills/prep/SKILL.md" | head -n 1 | tr -d '`')"
if [ -n "$cmd" ]; then
  same "18 a set variable: prints set" "$(NAME=dummy-secret-value "$shell" -c "$cmd")" set
  same "18 an unset variable: prints nothing" "$(unset NAME; "$shell" -c "$cmd")" ""
  refuse "18 the value is never printed, even with tracing on" \
    contains "$(NAME=dummy-secret-value "$shell" -xc "$cmd" 2>&1)" dummy-secret-value
else
  bad "18 prep's text has a command that checks an environment variable by name"
fi

printf '\n%d checks: %d passed, %d failed\n' "$((pass + fail))" "$pass" "$fail"
[ "$fail" -eq 0 ]
