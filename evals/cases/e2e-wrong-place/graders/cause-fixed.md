---
type: regex
target: { source: file, path: money.py }
pattern: '"""\n    whole, _, part = text\.partition\("\."\)\n    return int\(whole\) \* 100 \+ int\(part or 0\)'
match: not_contains
---
