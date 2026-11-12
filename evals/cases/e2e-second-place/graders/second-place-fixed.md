---
type: regex
target: { source: file, path: report.py }
pattern: '"""\n    return \[f"\{name\}: reorder" for name, count in items if count < limit\]'
match: not_contains
---
