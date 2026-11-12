#!/usr/bin/env bash
# Runs the cases in evals/cases against two versions of the skills and prints
# old against new. Every run is a real model call on your account.
# Usage: [OLD=<rev>] [NEW=<rev>] [MODEL=<model>] bash evals/compare.sh [claude plugin eval options]
# Example: bash evals/compare.sh --case secret-by-name --runs 1
# On macOS the eval's sandbox blocks git and plain `mktemp -d`, so the runs
# work without both, in both arms alike.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
old="${OLD:-b936fd9}"
new="${NEW:-HEAD}"
model="${MODEL:-claude-opus-5-5}"
out="$repo/evals/results/$(date +%Y-%m-%d-%H%M%S)"
work="$(mktemp -d)"
trap 'rm -rf "${work:?}"' EXIT
mkdir -p "$out"

for arm in old new; do
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

# Both arms run at once, so a slow hour or a model change hits both alike.
for arm in old new; do
  claude plugin eval "$work/$arm" --trust-plugin --scaffold --ablation none --no-publish \
    --model "$model" --judge-model claude-sonnet-5-5 --output-dir "$out/$arm" \
    "$@" --allow-tools Bash Write Edit > "$out/$arm.log" 2>&1 &
done
wait
python3 -I "$repo/evals/table.py" "$out"
