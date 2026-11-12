---
type: regex
target: { source: file, path: stock.py }
pattern: '"""\n    return \[name for name, count in items if count < limit\]'
match: not_contains
---
