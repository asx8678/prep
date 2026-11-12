#!/usr/bin/env bash
# Runs the cases in evals/cases against two versions of the skills and prints
# old against new. With OLD=none it runs them with the skills at NEW and with
# no skill at all, and shows the eval tool's own report of both.
# Every run is a real model call on your account.
# Usage: [OLD=<rev>|none] [NEW=<rev>] [MODEL=<model>] bash evals/compare.sh --case <glob> [claude plugin eval options]
# --case is required: without it the eval tool would run every case, which
# nobody should start by accident. --case '*' runs every case on purpose.
# Examples: bash evals/compare.sh --case secret-by-name --runs 1
#           OLD=none bash evals/compare.sh --case 'e2e-*' --runs 1
# With OLD=none the exit code is the eval tool's. It is 1 when a case scores
# below 1.0 with the skills, which is a result and not a failure of this
# script; the results folder is printed either way.
# On macOS the runs have no git. The eval's sandbox blocks /usr/bin/git,
# which is Apple's shim, and four ways around it failed on 2026-11-12: a
# wrapper script in the temp folder, in /private/tmp or in a case's
# `add_dirs` folder, and the real git's folder on PATH. The `git-ran`
# grader of the e2e cases shows whether git worked. Plain `mktemp -d` is
# blocked too. Both arms get the same.
set -euo pipefail
# 64, not 1 or 2: those are the eval tool's codes, which OLD=none passes on.
case " $* " in
  *" --case "* | *" --case="*) ;;
  *) echo "evals/compare.sh: --case <glob> is required; --case '*' runs every case" >&2; exit 64 ;;
esac
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
old="${OLD:-b936fd9}"
new="${NEW:-HEAD}"
model="${MODEL:-claude-opus-5-5}"
out="$repo/evals/results/$(date +%Y-%m-%d-%H%M%S)"
work="$(mktemp -d)"
trap 'rm -rf "${work:?}"' EXIT
mkdir -p "$out"

arms="old new"
if [ "$old" = none ]; then arms="new"; fi
for arm in $arms; do
  rev="${!arm}"
  dir="$work/$arm"
  mkdir -p "$dir/.claude-plugin" "$dir/skills/prep" "$dir/skills/impl"
  printf '{"name": "prep"}\n' > "$dir/.claude-plugin/plugin.json"
  for skill in prep impl; do
    git -C "$repo" show "$rev:skills/$skill/SKILL.md" > "$dir/skills/$skill/SKILL.md"
  done
  cp -R "$repo/evals/cases" "$dir/evals"
  echo "$arm = $rev on $model: prep $(git hash-object "$dir/skills/prep/SKILL.md"), impl $(git hash-object "$dir/skills/impl/SKILL.md")" | tee -a "$out/arms.txt"
done

# eval_arm ARM ABLATION [OPTIONS...]: runs the cases on the plugin folder of ARM
eval_arm() {
  local arm="$1" ablation="$2"
  shift 2
  claude plugin eval "$work/$arm" --trust-plugin --scaffold --ablation "$ablation" --no-publish \
    --model "$model" --judge-model claude-sonnet-5-5 --output-dir "$out/$arm" \
    "$@" --allow-tools Bash Write Edit
}

if [ "$old" = none ]; then
  code=0
  eval_arm new with-without "$@" || code=$?
  echo "Results: $out/new"
  exit "$code"
fi

# Both arms run at once, so a slow hour or a model change hits both alike.
for arm in old new; do
  eval_arm "$arm" none "$@" > "$out/$arm.log" 2>&1 &
done
wait
python3 -I "$repo/evals/table.py" "$out"
