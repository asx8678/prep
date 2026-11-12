#!/usr/bin/env bash
# Checks the installer, the commands inside the skills, and the eval cases
# and evals/compare.sh, without a model call.
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
max_prep_bytes=28810

work="$(mktemp -d)" || exit 1
work="$(cd "$work" && pwd -P)"
trap 'rm -rf "$work"' EXIT

real_path="$PATH"
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
is_under() { case "$1" in "$2"/*) return 0 ;; esac; return 1; }
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

homes=0
# new_home: makes HOME a new, empty folder
new_home() {
  homes=$((homes + 1))
  export HOME="$work/home$homes"
  mkdir -p "$HOME"
}

fake_bin=""
# run DIR [ARGS...]: runs the installer in DIR; sets $rc, keeps the output in
# $work/out. The menu gets $answers as its input, which is nothing unless a
# check sets it: answers='1\n3\n' run DIR
run() {
  local dir="$1"; shift
  printf '%b' "${answers:-}" |
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
run "$work/nogit" install
same "3 exit 1" "$rc" 1
expect "3 nothing is written" is_empty_dir "$work/nogit"

echo "== 4. A fresh install"
new_repo; a="$r"
run "$a" install
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
run "$sub/deep/down" install
expect "4 from a subfolder: the skills go to the root" is_skill "$sub/.agents/skills/prep/SKILL.md" prep
refuse "4 from a subfolder: nothing is put in the subfolder" test -e "$sub/deep/down/.agents"

echo "== 5. A second run"
before="$(tree "$a")"
run "$a" install
same "5 exit 0" "$rc" 0
expect "5 nothing changes" test "$(tree "$a")" = "$before"

echo "== 6. An upgrade"
new_repo; up="$r"
run "$up" install
if old_version prep "$up/.agents/skills/prep/SKILL.md"; then
  refuse "6 (setup) the older version differs from today's" is_skill "$up/.agents/skills/prep/SKILL.md" prep
  run "$up" install
  same "6 exit 0" "$rc" 0
  expect "6 an older shipped version is replaced" is_skill "$up/.agents/skills/prep/SKILL.md" prep
  refuse "6 no new version is left waiting" test -e "$up/.git/prep-install/prep/SKILL.md"
else
  bad "6 $no_history"
fi

echo "== 7. Your edit"
new_repo; ed="$r"
run "$ed" install
add_rule "$ed/.agents/skills/prep/SKILL.md"
sum="$(cksum < "$ed/.agents/skills/prep/SKILL.md")"
run "$ed" install
same "7 exit 0" "$rc" 0
same "7 an edited skill file is kept" "$(cksum < "$ed/.agents/skills/prep/SKILL.md")" "$sum"
expect "7 the new version waits in .git/prep-install/" is_skill "$ed/.git/prep-install/prep/SKILL.md" prep
expect "7 the other skill stays up to date" is_skill "$ed/.agents/skills/impl/SKILL.md" impl

echo "== 8. The choice of tools, and wrong arguments"
new_repo; t="$r"
run "$t" install claude
expect "8 claude: .claude/skills/prep is linked" is_link_to "$t/.claude/skills/prep" "$links_to/prep"
refuse "8 claude: no .kiro folder" test -e "$t/.kiro"
expect "8 claude: the real copy is in .agents/skills" is_skill "$t/.agents/skills/impl/SKILL.md" impl
new_repo; t="$r"
run "$t" install kiro pi
expect "8 kiro pi: .kiro/skills/impl is linked" is_link_to "$t/.kiro/skills/impl" "$links_to/impl"
refuse "8 kiro pi: no .claude folder" test -e "$t/.claude"
new_repo; t="$r"
run "$t" install CLAUDE
expect "8 CLAUDE in upper case is accepted" is_link_to "$t/.claude/skills/prep" "$links_to/prep"
new_repo; t="$r"
clean="$(tree "$t")"
for args in "codex" "--bogus" "--copies --undo-copies" "--global --copies" "--global --undo-copies" \
  "remove claude" "update kiro"; do
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
run "$own" install
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
  run "$c" install
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
    run "$c" install
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
run "$lk" install
same "11 exit 0" "$rc" 0
expect "11 the skill opens through the linked folder" is_skill "$lk/.claude/skills/prep/SKILL.md" prep
expect "11 it is a marked copy, because a link would not open" is_copy "$work/elsewhere/prep"
expect "11 the other tool still gets links" is_link_to "$lk/.kiro/skills/prep" "$links_to/prep"

echo "== 12. A git worktree"
new_repo; main="$r"
wt="$work/worktree"
git -C "$main" worktree add -q "$wt" -b side
run "$wt" install
same "12 exit 0" "$rc" 0
expect "12 the skills are installed in the worktree" is_skill "$wt/.agents/skills/prep/SKILL.md" prep
refuse "12 nothing is put in the main folder" test -e "$main/.agents"
add_rule "$wt/.agents/skills/prep/SKILL.md"
run "$wt" install
stage="$(cd "$wt" && git rev-parse --git-path prep-install)"
case "$stage" in /*) ;; *) stage="$wt/$stage" ;; esac
expect "12 the kept new version is in the worktree's git folder" is_skill "$stage/prep/SKILL.md" prep
refuse "12 that git folder is not inside the worktree" test -d "$wt/.git"

echo "== 13. Windows line endings"
new_repo; crlf="$r"
run "$crlf" install
git -C "$crlf" config core.autocrlf true
f="$crlf/.agents/skills/prep/SKILL.md"
awk '{ printf "%s\r\n", $0 }' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
refuse "13 (setup) the installed file now has Windows line endings" is_skill "$f" prep
run "$crlf" install
same "13 exit 0" "$rc" 0
expect "13 with core.autocrlf=true the file is updated" is_skill "$f" prep
refuse "13 and it is not kept as an edit of yours" test -e "$crlf/.git/prep-install/prep/SKILL.md"

echo "== 14. A clone without link support (the default on Windows)"
new_repo; win="$r"
run "$win" install
git -C "$win" add -A . && git -C "$win" commit -q -m "add the skills"
git -C "$win" config core.symlinks false
rm "$win/.claude/skills/prep" "$win/.claude/skills/impl" "$win/.kiro/skills/prep" "$win/.kiro/skills/impl"
git -C "$win" checkout -q -- .claude .kiro
fake_bin="$work/ln-copies"
expect "14 (setup) git checks a link out as a small text file" is_text_link "$win/.claude/skills/prep" "$links_to/prep"
run "$win" install
same "14 exit 0" "$rc" 0
for tool in claude kiro; do
  for name in prep impl; do
    expect "14 .$tool/skills/$name: the text file is left alone" is_text_link "$win/.$tool/skills/$name" "$links_to/$name"
  done
done
same "14 git status stays clean" "$(git -C "$win" status --short)" ""
run "$win" install --copies
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
run "$win" install --copies
run "$win" remove
same "14 remove: exit 0" "$rc" 0
refuse "14 remove: a local copy is removed" test -e "$win/.claude/skills/prep"
expect "14 remove: git sees that its link is gone" contains "$(git -C "$win" status --short)" "D .claude/skills/prep"
fake_bin=""

echo "== 15. prep's throwaway copy (the command in the skill text)"
code_block "git clone -q" > "$work/copy.sh"
expect "15 the command is in prep's text" test -s "$work/copy.sh"
# try DIR: runs the command in DIR; sets $rc and $copy (the folder it prints)
try() {
  copy="$(cd "$1" && TMPDIR="$work/mk" "$shell" "$work/copy.sh" 2> "$work/out")"
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
# Plain `mktemp -d` ignores TMPDIR on macOS; a sandbox may allow only TMPDIR.
expect "15 the copy is made in TMPDIR" is_under "$copy" "$work/mk"
same "15 the folder it prints is the one to delete" "$(dirname "$copy")" "$work/mk"
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
git config --global clone.defaultRemoteName upstream
try "$plain"
same "15 with clone.defaultRemoteName set: exit 0" "$rc" 0
same "15 with clone.defaultRemoteName set: the copy has no remote" "$(git -C "$copy" remote 2>&1)" ""
git config --global --unset clone.defaultRemoteName
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
printf 'staged\n' > "$st/a.txt"; git -C "$st" add a.txt; s4="$(state "$st")"
printf 'staged again\n' > "$st/a.txt"; git -C "$st" add a.txt; s5="$(state "$st")"
refuse "16 a staged file that is changed and staged again changes the output" test "$s5" = "$s4"

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
same "17 the third line names the commit" "$(printf '%s\n' "$first" | sed -n 3p)" "commit: $(git -C "$st" rev-parse --short HEAD)"
same "17 outside git the commit line is empty" "$(cd "$work/nogit" && "$shell" "$work/start.sh" 2>/dev/null | sed -n 3p)" "commit: "
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

echo "== 19. prep's command that counts earlier tasks (in the skill text)"
look="$(grep -o '`grep [^`]*uniq -c`' "$repo/skills/prep/SKILL.md" | head -n 1 | tr -d '`')"
expect "19 the command is in prep's text" test -n "$look"
log="$work/log.md"
printf '%s\n' \
  '2026-11-11 | payments-api | fix-cves | briefed | Update vulnerable packages' \
  '2026-11-12 | payments-api | fix-cves | done | missed: nothing' \
  '2026-11-13 | shop | add-endpoint | briefed | Add an endpoint' > "$log"
counts="$("$shell" -c "$(printf '%s' "$look" | sed "s|<log>|$log|")" 2>&1)"
same "19 a task that was briefed and then done counts once" \
  "$(printf '%s\n' "$counts" | awk '$2 == "fix-cves" { print $1 }')" 1
same "19 a task that was only briefed counts once" \
  "$(printf '%s\n' "$counts" | awk '$2 == "add-endpoint" { print $1 }')" 1

echo "== 20. prep's command for a secret's key in a settings file (in the skill text)"
cmd="$(grep -o '`grep -c [^`]*`' "$repo/skills/prep/SKILL.md" | head -n 1 | tr -d '`')"
expect "20 the command is in prep's text" test -n "$cmd"
printf 'region = "eu"\ndb_password = "dummy-secret-value"\n' > "$work/settings.conf"
same "20 a secret's key that is set: prints only a count" \
  "$("$shell" -c "$(printf '%s' "$cmd" | sed "s|<key>|db_password|; s|<file>|$work/settings.conf|")" 2>&1)" 1

echo "== 21. A global install (--global)"
new_home
new_repo; g="$r"
clean="$(tree "$g")"
run "$g" install --global
same "21 exit 0" "$rc" 0
for name in prep impl; do
  expect "21 ~/.agents/skills/$name/SKILL.md is the skill" is_skill "$HOME/.agents/skills/$name/SKILL.md" "$name"
  for tool in claude kiro; do
    expect "21 ~/.$tool/skills/$name links to $links_to/$name" is_link_to "$HOME/.$tool/skills/$name" "$links_to/$name"
    expect "21 ~/.$tool/skills/$name/SKILL.md opens" is_skill "$HOME/.$tool/skills/$name/SKILL.md" "$name"
  done
done
expect "21 nothing is written to the repository it is run in" test "$(tree "$g")" = "$clean"
refuse "21 no .briefs/ is made in that repository" test -e "$g/.briefs"
refuse "21 ~/.briefs/ is not made" test -e "$HOME/.briefs"
refuse "21 no empty folder for waiting versions is left" test -e "$HOME/.agents/prep-install"
before="$(tree "$HOME")"
run "$work/nogit" install --global
same "21 outside a repository: exit 0" "$rc" 0
expect "21 outside a repository: nothing is written there" is_empty_dir "$work/nogit"
expect "21 a second run changes nothing" test "$(tree "$HOME")" = "$before"
new_home
run "$work/nogit" install --global claude
expect "21 claude: ~/.claude/skills/prep is linked" is_link_to "$HOME/.claude/skills/prep" "$links_to/prep"
refuse "21 claude: no ~/.kiro folder" test -e "$HOME/.kiro"

echo "== 22. A global install next to what is already in the home folder"
new_home
mkdir -p "$HOME/.claude/skills/prep" "$HOME/.claude/skills/impl" "$HOME/.claude/skills/other" \
  "$HOME/.kiro/skills/impl" "$HOME/mine"
cp "$repo/skills/prep/SKILL.md" "$HOME/.claude/skills/prep/"
cp "$repo/skills/impl/SKILL.md" "$HOME/.claude/skills/impl/"
add_rule "$HOME/.claude/skills/impl/SKILL.md"
sum="$(cksum < "$HOME/.claude/skills/impl/SKILL.md")"
printf 'another skill\n' > "$HOME/.claude/skills/other/SKILL.md"
printf 'mine\n' > "$HOME/.kiro/skills/impl/note.txt"
ln -s ../../mine "$HOME/.kiro/skills/prep"
other="$(tree "$HOME/.claude/skills/other")"
run "$work/nogit" install --global
same "22 exit 0" "$rc" 0
expect "22 a skill copied by hand becomes a link" is_link_to "$HOME/.claude/skills/prep" "$links_to/prep"
same "22 a skill copied by hand and then edited is kept" "$(cksum < "$HOME/.claude/skills/impl/SKILL.md")" "$sum"
expect "22 your own link is left alone" is_link_to "$HOME/.kiro/skills/prep" ../../mine
expect "22 your own folder is left alone" test -f "$HOME/.kiro/skills/impl/note.txt"
refuse "22 your own folder gets no skill file" test -e "$HOME/.kiro/skills/impl/SKILL.md"
expect "22 another skill is left alone" test "$(tree "$HOME/.claude/skills/other")" = "$other"

echo "== 23. Update"
new_home
run "$work/nogit" update --global
same "23 nothing installed: exit 0" "$rc" 0
expect "23 nothing installed: nothing is written" is_empty_dir "$HOME"
run "$work/nogit" install --global claude
if old_version prep "$HOME/.agents/skills/prep/SKILL.md"; then
  run "$work/nogit" update --global
  same "23 exit 0" "$rc" 0
  expect "23 an older shipped version is replaced" is_skill "$HOME/.agents/skills/prep/SKILL.md" prep
else
  bad "23 $no_history"
fi
expect "23 the tool that was set up keeps its link" is_link_to "$HOME/.claude/skills/prep" "$links_to/prep"
refuse "23 a tool that was not set up is not added" test -e "$HOME/.kiro"
add_rule "$HOME/.agents/skills/prep/SKILL.md"
sum="$(cksum < "$HOME/.agents/skills/prep/SKILL.md")"
run "$work/nogit" update --global
same "23 an edited skill file is kept" "$(cksum < "$HOME/.agents/skills/prep/SKILL.md")" "$sum"
expect "23 the new version waits in ~/.agents/prep-install/" is_skill "$HOME/.agents/prep-install/prep/SKILL.md" prep
take="$(sed -n 's/^  Take it:  //p' "$work/out")"
( cd "$work/nogit" && "$shell" -c "$take" ) > /dev/null 2>&1
expect "23 the printed command that takes it works from another folder" is_skill "$HOME/.agents/skills/prep/SKILL.md" prep
new_home
mkdir -p "$HOME/.claude/skills"
cp -R "$repo/skills/prep" "$HOME/.claude/skills/prep"
run "$work/nogit" update --global
expect "23 a skill copied by hand counts as installed" is_link_to "$HOME/.claude/skills/prep" "$links_to/prep"
new_repo; u="$r"
run "$u" install kiro
run "$u" update
same "23 in a repository: exit 0" "$rc" 0
refuse "23 in a repository: a tool that was not set up is not added" test -e "$u/.claude"

echo "== 24. Remove"
new_repo; gone="$r"
clean="$(tree "$gone")"
run "$gone" install
run "$gone" remove
same "24 in a repository: exit 0" "$rc" 0
expect "24 in a repository: every file and link of the install is gone" test "$(tree "$gone")" = "$clean"
for name in prep impl; do
  for dir in .agents .claude .kiro; do
    refuse "24 in a repository: $dir/skills/$name is gone" test -e "$gone/$dir/skills/$name"
  done
done
expect "24 in a repository: .briefs/ stays" test -d "$gone/.briefs"
new_home
mkdir -p "$HOME/.agents/skills/mine" "$HOME/.claude/skills" "$HOME/.briefs"
printf 'my skill\n' > "$HOME/.agents/skills/mine/SKILL.md"
ln -s "$links_to/mine" "$HOME/.claude/skills/mine"
printf 'my record\n' > "$HOME/.briefs/log.md"
mine="$(tree "$HOME")"
run "$work/nogit" install --global
run "$work/nogit" remove --global
same "24 --global: exit 0" "$rc" 0
expect "24 --global: only what was there before is left" test "$(tree "$HOME")" = "$mine"
refuse "24 --global: ~/.agents/skills/prep is gone" test -e "$HOME/.agents/skills/prep"
expect "24 --global: the folders other skills use stay" test -d "$HOME/.claude/skills"
run "$work/nogit" install --global
add_rule "$HOME/.agents/skills/prep/SKILL.md"
sum="$(cksum < "$HOME/.agents/skills/prep/SKILL.md")"
printf 'notes\n' > "$HOME/.agents/skills/impl/notes.md"
mkdir -p "$HOME/.agents/prep-install/prep"
run "$work/nogit" remove --global
same "24 a skill file you changed is kept" "$(cksum < "$HOME/.agents/skills/prep/SKILL.md")" "$sum"
expect "24 and so are the links to it" is_link_to "$HOME/.claude/skills/prep" "$links_to/prep"
refuse "24 the unchanged skill file is removed" test -e "$HOME/.agents/skills/impl/SKILL.md"
refuse "24 and so are the links to it" test -L "$HOME/.claude/skills/impl"
expect "24 a file of yours next to it is kept" test -f "$HOME/.agents/skills/impl/notes.md"
refuse "24 the folder for waiting versions is removed" test -e "$HOME/.agents/prep-install"
new_home
mkdir -p "$HOME/.claude/skills" "$HOME/.kiro/skills/impl" "$HOME/mine"
cp -R "$repo/skills/prep" "$HOME/.claude/skills/prep"
ln -s ../../mine "$HOME/.claude/skills/impl"
printf 'mine\n' > "$HOME/.kiro/skills/impl/note.txt"
run "$work/nogit" remove --global
refuse "24 a skill copied by hand is removed" test -e "$HOME/.claude/skills/prep"
expect "24 your own link is left alone" is_link_to "$HOME/.claude/skills/impl" ../../mine
expect "24 your own folder is left alone" test -f "$HOME/.kiro/skills/impl/note.txt"

echo "== 25. The menu (no install, update or remove on the command line)"
new_home
new_repo; m="$r"
clean="$(tree "$m")"
answers='1\n1\n\n' run "$m"
same "25 every project, install: exit 0" "$rc" 0
expect "25 every project, install: the skills are in the home folder" is_skill "$HOME/.agents/skills/prep/SKILL.md" prep
expect "25 every project, install: nothing is written to the repository" test "$(tree "$m")" = "$clean"
if old_version prep "$HOME/.agents/skills/prep/SKILL.md"; then
  answers='1\n2\n' run "$m"
  expect "25 every project, update: an older shipped version is replaced" is_skill "$HOME/.agents/skills/prep/SKILL.md" prep
else
  bad "25 $no_history"
fi
before="$(tree "$HOME")"
answers='2\n1\n\n' run "$m"
expect "25 this repository, install: the skills are in the repository" is_skill "$m/.agents/skills/prep/SKILL.md" prep
expect "25 this repository, install: the home folder is unchanged" test "$(tree "$HOME")" = "$before"
answers='2\n3\n' run "$m"
expect "25 this repository, remove: the repository is as it was" test "$(tree "$m")" = "$clean"
expect "25 this repository, remove: the home folder is unchanged" test "$(tree "$HOME")" = "$before"
answers='1\n3\n' run "$m"
refuse "25 every project, remove: ~/.agents/skills/prep is gone" test -e "$HOME/.agents/skills/prep"
new_home
answers='1\n\n' run "$work/nogit"
expect "25 outside a repository it asks only what to do" is_skill "$HOME/.agents/skills/prep/SKILL.md" prep
new_home
answers='1\n\n' run "$m" --global
expect "25 with --global it asks only what to do" is_skill "$HOME/.agents/skills/prep/SKILL.md" prep
new_home
answers='1\n' run "$m" --copies
same "25 --copies and every project: exit 2" "$rc" 2
expect "25 --copies and every project: nothing is written" test "$(tree "$m")$(ls -A "$HOME")" = "$clean"
for typed in 'q\n' '1\nq\n' '1\n1\nq\n'; do
  answers="$typed" run "$m"
  same "25 '$typed': exit 0" "$rc" 0
  expect "25 '$typed': nothing is written" test "$(tree "$m")$(ls -A "$HOME")" = "$clean"
done
for typed in '' '\n' 'x\n' '3\n' '1\n9\n' '1\n' '1\n1\n' '1\n1\n9\n' '1\n1\n1\n2\n3\n\n'; do
  answers="$typed" run "$m"
  same "25 '$typed': exit 1" "$rc" 1
  expect "25 '$typed': nothing is written" test "$(tree "$m")$(ls -A "$HOME")" = "$clean"
done

echo "== 26. The menu's choice of tools"
new_home
answers='1\n1\n2\n\n' run "$m"
same "26 Kiro switched off: exit 0" "$rc" 0
expect "26 Kiro switched off: ~/.claude/skills/prep is linked" is_link_to "$HOME/.claude/skills/prep" "$links_to/prep"
refuse "26 Kiro switched off: no ~/.kiro folder" test -e "$HOME/.kiro"
expect "26 nothing is written to the repository" test "$(tree "$m")" = "$clean"
answers='1\n1\n1\n\n' run "$m"
expect "26 Claude Code switched off later: its links stay" is_link_to "$HOME/.claude/skills/prep" "$links_to/prep"
expect "26 Claude Code switched off later: Kiro is added" is_link_to "$HOME/.kiro/skills/prep" "$links_to/prep"
new_home
answers='1\n1\n2\n2\n\n' run "$m"
expect "26 Kiro switched off and on again: ~/.kiro/skills/prep is linked" is_link_to "$HOME/.kiro/skills/prep" "$links_to/prep"
new_home
answers='1\n1\n3\n\n' run "$m"
expect "26 Pi switched off: the real copy is still in ~/.agents/skills" is_skill "$HOME/.agents/skills/prep/SKILL.md" prep
expect "26 Pi switched off: the others are linked" is_link_to "$HOME/.kiro/skills/impl" "$links_to/impl"
new_home
answers='1\n1\n1\n2\n\n' run "$m"
same "26 only Pi left on: exit 0" "$rc" 0
expect "26 only Pi: the skills are in ~/.agents/skills" is_skill "$HOME/.agents/skills/impl/SKILL.md" impl
refuse "26 only Pi: no ~/.claude folder" test -e "$HOME/.claude"
refuse "26 only Pi: no ~/.kiro folder" test -e "$HOME/.kiro"
new_home
answers='1\n1\n' run "$m" claude
same "26 a tool named on the command line is not asked for: exit 0" "$rc" 0
expect "26 a tool named on the command line: ~/.claude/skills/prep is linked" is_link_to "$HOME/.claude/skills/prep" "$links_to/prep"
refuse "26 a tool named on the command line: no ~/.kiro folder" test -e "$HOME/.kiro"

echo "== 27. prep's example of a check that starts a server (in the skill text)"
example="$(grep -o '`([^`]*<start> & [^`]*`' "$repo/skills/prep/SKILL.md" | head -n 1 | tr -d '`')"
expect "27 the example is in prep's text" test -n "$example"
mkdir "$work/site" && printf 'ok\n' > "$work/site/ok.txt"
port=$((10000 + $$ % 20000))
server="http.server --bind 127.0.0.1 $port"
# check_url FILE: runs the example for FILE on a local server; sets $rc. The
# output goes to a file: a server left running would keep a pipe open, and
# the test would wait for it instead of failing.
check_url() {
  ( cd "$work/site" && "$shell" -c "$(printf '%s' "$example" |
    sed "s|<start>|python3 -m $server|; s|<url>|http://127.0.0.1:$port/$1|g")" ) > "$work/out" 2>&1
  rc=$?
}
# no_server: waits until the server is gone, because kill does not wait for
# it; fails when it still runs after 5 seconds. pgrep exits 1 when nothing
# matches: any other failure, such as no pgrep at all, must not count as gone.
no_server() {
  local tries=0
  until pgrep -f "$server" > /dev/null 2>&1; [ $? -eq 1 ]; do
    tries=$((tries + 1))
    [ "$tries" -lt 50 ] || return 1
    sleep 0.1
  done
}
check_url ok.txt
same "27 the check passes although the server needs time to start" "$rc" 0
# The second server needs the port that the first one held.
no_server
check_url missing.txt
refuse "27 with a URL that does not exist the check fails" test "$rc" -eq 0
expect "27 no server is left running" no_server
# A server that was there before the check: the test's own, started outside
# the script's jobs so that stopping it prints nothing.
( cd "$work/site" && exec python3 -m $server > /dev/null 2>&1 & )
curl -s -o /dev/null --retry 5 --retry-connrefused "http://127.0.0.1:$port/ok.txt"
check_url ok.txt
same "27 with a server that already answers, the check fails" "$rc" 1
check_url missing.txt
same "27 the same for a URL that does not exist there" "$rc" 1
# This stops the test's own server; a failed check must not leave one behind
# either.
pkill -f "$server"

echo "== 28. The end-to-end cases tell a right fix from a wrong one"
# A state copies files over the scaffolded project, so Python must not keep
# a compiled copy of the file that was there before.
export PYTHONDONTWRITEBYTECODE=1
cat > "$work/judge.py" <<'PY'
"""What a case's acceptance test or its file graders say about a project.

Run it in the project's folder:
  judge.py test <acceptance test>   prints pass or fail, or error when the test itself broke
  judge.py graders <case folder>    prints pass when every file grader passes, else fail
A crash prints nothing, so a check never takes it for a verdict.
"""
import os
import re
import sys
import unittest
from pathlib import Path

kind, where = sys.argv[1], Path(sys.argv[2])
if kind == "test":
    sys.path.insert(0, os.getcwd())
    suite = unittest.defaultTestLoader.discover(str(where.parent), pattern=where.name)
    result = unittest.TextTestRunner(stream=sys.stderr).run(suite)
    print("error" if result.errors or not result.testsRun else "fail" if result.failures else "pass")
else:
    # A file grader is a regex grader whose target is a file. The eval tool
    # reads the pattern as JavaScript; these use only what Python shares.
    verdicts = []
    for grader in sorted(where.glob("graders/*.md")):
        fields = dict(line.split(": ", 1) for line in grader.read_text().split("---\n")[1].splitlines())
        target = re.fullmatch(r"\{\s*source:\s*file,\s*path:\s*(\S+)\s*\}", fields.get("target", ""))
        if fields["type"] == "regex" and target:
            pattern = re.fullmatch("'(.*)'", fields["pattern"]).group(1).replace("''", "'")
            found = re.search(pattern, Path(target.group(1)).read_text()) is not None
            verdicts.append(found == {None: True, "not_contains": False}[fields.get("match")])
    if not verdicts:
        sys.exit(f"no file grader in {where}")
    print("pass" if all(verdicts) else "fail")
PY
# says KIND DIR: what the acceptance test (KIND test) or the file graders
# (KIND graders) of the case say about the project in DIR
says() {
  local about="$self/acceptance_test.py"
  [ "$1" = test ] || about="$e2e"
  ( cd "$2" && python3 "$work/judge.py" "$1" "$about" ) 2> "$work/out"
}
# judge STATE DIR VERDICT: both must say VERDICT (pass or fail) about DIR
judge() {
  local tested="the acceptance test passes" graded="every file grader passes"
  [ "$3" = pass ] || { tested="the acceptance test fails"; graded="a file grader fails"; }
  same "28 $name, $1: $tested" "$(says test "$2")" "$3"
  same "28 $name, $1: $graded" "$(says graders "$2")" "$3"
}
for e2e in "$repo"/evals/cases/e2e-*; do
  name="$(basename "$e2e")"
  self="$repo/evals/selftest/$name"
  base="$work/e2e/$name/scaffolded"
  mkdir -p "$base"
  ( cd "$base" && "$shell" "$e2e/scaffold.sh" ) > "$work/out" 2>&1
  same "28 $name: the scaffold runs" "$?" 0
  ( cd "$base" && python3 -m unittest ) > "$work/out" 2>&1
  same "28 $name: the project's own tests pass as scaffolded" "$?" 0
  judge "as scaffolded" "$base" fail
  for state in "$self"/wrong* "$self"/fixed*; do
    dir="$work/e2e/$name/$(basename "$state")"
    { cp -R "$base" "$dir" && cp -R "$state/." "$dir/"; } 2> "$work/out"
    case "$(basename "$state")" in wrong*) want=fail ;; *) want=pass ;; esac
    judge "$(basename "$state")" "$dir" "$want"
  done
done

echo "== 29. evals/compare.sh, with a fake claude"
mkdir "$work/fake-claude"
cat > "$work/fake-claude/claude" <<'FAKE'
#!/bin/sh
# Stands in for `claude plugin eval <plugin folder> ...`: records the call,
# writes an empty result where --output-dir says, and exits with $FAKE_EXIT.
call="$FAKE_CALLS/$$"
mkdir -p "$call"
printf '%s ' "$@" > "$call/args"
cp "$3/skills/prep/SKILL.md" "$call/prep.md"
git="$(command -v git)"
printf '%s\n' "$git" > "$call/git"
head -c 1000 "$git" > "$call/git-start"
echo "summary from the eval tool"
while [ $# -gt 0 ]; do
  [ "$1" = --output-dir ] && out="$2"
  shift
done
mkdir -p "$out"
printf '%s\n' '{"cases": [], "costUsd": 0, "durationSeconds": 0, "partial": false}' > "$out/aggregate-result.json"
exit "$FAKE_EXIT"
FAKE
chmod +x "$work/fake-claude/claude"
# The clone holds what is committed; the script and the cases are the
# working tree's. table.py comes later: with OLD=none the script must not
# need it, and running it there would also exit 1.
c="$work/evalrepo"
git clone -q "$repo" "$c" > "$work/out" 2>&1
rm -rf "$c/evals" && mkdir "$c/evals" && cp -R "$repo/evals/cases" "$repo/evals/compare.sh" "$c/evals/"
calls="$work/claude-calls"
# compare EXIT [OPTIONS...]: runs the script with a fake claude that exits
# with EXIT; sets $rc and keeps the output in $work/out
compare() {
  local code="$1"; shift
  rm -rf "$calls"
  ( cd "$work/nogit" && FAKE_CALLS="$calls" FAKE_EXIT="$code" PATH="$work/fake-claude:$real_path" \
    "$shell" "$c/evals/compare.sh" "$@" ) > "$work/out" 2>&1
  rc=$?
}
unset OLD NEW MODEL
results_before="$(ls -A "$repo/evals/results" 2>/dev/null)"
OLD=none compare 1 --case 'e2e-*' --runs 1
same "29 OLD=none: the exit code is the eval tool's" "$rc" 1
same "29 OLD=none: claude plugin eval is called once" "$(($(ls "$calls" 2>/dev/null | wc -l)))" 1
call="$calls/$(ls "$calls" 2>/dev/null | head -n 1)"
args="$(cat "$call/args" 2>/dev/null)"
expect "29 OLD=none: it asks for runs with the skills and without" contains "$args" "--ablation with-without "
expect "29 OLD=none: the options it was given are passed on" contains "$args" "--case e2e-* --runs 1 "
git -C "$c" show HEAD:skills/prep/SKILL.md > "$work/prep-at-head.md"
expect "29 OLD=none: the plugin folder holds prep's text at NEW" cmp -s "$call/prep.md" "$work/prep-at-head.md"
expect "29 OLD=none: the eval tool's output is shown" grep -q "summary from the eval tool" "$work/out"
named="$(grep -o "$c/evals/results/[^ ]*" "$work/out" | tail -n 1)"
expect "29 OLD=none: the output names the results folder" test -f "$named/aggregate-result.json"
if xcode_git="$(xcrun -f git 2>/dev/null)"; then
  same "29 git for the runs is a wrapper around the git that xcrun names" \
    "$(cat "$call/git-start" 2>/dev/null)" "$(printf '#!/bin/sh\nexec "%s" "$@"' "$xcode_git")"
else
  same "29 git for the runs is the usual git" "$(cat "$call/git" 2>/dev/null)" "$(command -v git)"
fi
cp "$repo/evals/table.py" "$c/evals/"
compare 0 --case 'e2e-*' --runs 1
same "29 old against new: exit 0" "$rc" 0
same "29 old against new: claude plugin eval is called twice" "$(($(ls "$calls" 2>/dev/null | wc -l)))" 2
same "29 old against new: neither call asks for runs without the skills" \
  "$(($(cat "$calls"/*/args 2>/dev/null | grep -o -e '--ablation none ' | wc -l)))" 2
rm -rf "$c/evals/results"
compare 0 --runs 1
same "29 without --case: exit 64" "$rc" 64
same "29 without --case: claude plugin eval is not called" "$(($(ls "$calls" 2>/dev/null | wc -l)))" 0
refuse "29 without --case: no results folder is made" test -e "$c/evals/results"
compare 0 --case='e2e-*' --runs 1
same "29 --case=<glob> names the cases too: exit 0" "$rc" 0
# The fake claude writes a result without cases, so the table gets one from
# here: two runs of one end-to-end case on each arm.
# table_run PREP IMPL FIXED: a run as the eval tool records it, with true or
# false for each of the three graders
table_run() {
  printf '{"error": null, "graders": [{"name": "prep-fired", "passed": %s}, {"name": "impl-fired", "passed": %s}, {"name": "git-ran", "passed": true}, {"name": "second-place-fixed", "passed": %s}]}' "$@"
}
# table_result RUN RUN: the result file of one arm
table_result() {
  printf '{"cases": [{"name": "e2e-second-place", "arms": {"with": [%s, %s]}}], "costUsd": 0, "durationSeconds": 0, "partial": false}\n' "$@"
}
mkdir -p "$work/table/old" "$work/table/new"
table_result "$(table_run true true true)" "$(table_run false false false)" > "$work/table/old/aggregate-result.json"
table_result "$(table_run true true true)" "$(table_run true true true)" > "$work/table/new/aggregate-result.json"
python3 -I "$repo/evals/table.py" "$work/table" > "$work/out" 2>&1
same "29 the table counts a result only in runs where both skills started" \
  "$(awk '$2 == "second-place-fixed" { print $3, $4 }' "$work/out")" "1/1 2/2"
expect "29 the table lists a run where prep did not start as dropped" \
  grep -q "dropped: e2e-second-place, old: failed prep-fired" "$work/out"
same "29 nothing is written to this repository's evals/results/" "$(ls -A "$repo/evals/results" 2>/dev/null)" "$results_before"

printf '\n%d checks: %d passed, %d failed\n' "$((pass + fail))" "$pass" "$fail"
[ "$fail" -eq 0 ]
