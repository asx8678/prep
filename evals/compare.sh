#!/usr/bin/env bash
# Runs the cases in evals/cases against two versions of the skills and prints
# old against new. With OLD=none it runs them with the skills at NEW and with
# no skill at all, and shows the eval tool's own report of both.
# Every run is a real model call on your account.
# Usage: [OLD=<rev>|none] [NEW=<rev>] [MODEL=<model>] bash evals/compare.sh [claude plugin eval options]
# Examples: bash evals/compare.sh --case secret-by-name --runs 1
#           OLD=none bash evals/compare.sh --case 'e2e-*' --runs 1
# With OLD=none the exit code is the eval tool's. It is 1 when a case scores
# below 1.0 with the skills, which is a result and not a failure of this
# script; the results folder is printed either way.
# On macOS the eval's sandbox blocks /usr/bin/git, which is Apple's shim, and
# plain `mktemp -d`. For git, the runs get a wrapper around the git that
# `xcrun -f git` names, first on PATH; the `git-ran` grader of the e2e cases
# shows whether git then worked. `mktemp -d` stays blocked. Both arms get
# the same.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
old="${OLD:-b936fd9}"
new="${NEW:-HEAD}"
model="${MODEL:-claude-opus-5-5}"
out="$repo/evals/results/$(date +%Y-%m-%d-%H%M%S)"
work="$(mktemp -d)"
trap 'rm -rf "${work:?}"' EXIT
mkdir -p "$out"

# A link would not do: git looks for its helpers next to the link.
if xcode_git="$(xcrun -f git 2>/dev/null)"; then
  mkdir "$work/bin"
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$xcode_git" > "$work/bin/git"
  chmod +x "$work/bin/git"
  PATH="$work/bin:$PATH"
fi

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
