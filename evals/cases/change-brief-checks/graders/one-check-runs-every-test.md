---
type: regex
target: { source: file, path: .briefs/2026-11-12-000000-add-health.md }
pattern: '## Proof\n(?:(?!\n## )[\s\S])*?python3?(?: -[A-Za-z]+)* -m unittest(?:(?: discover)?(?: (?:-[vqfbc]|--\w+|-[spt] \S+))*(?=`|\s*(?:2>|\||;|&&|\n|$))|(?=[^`\n]*tests[./]test_routes)(?=[^`\n]*tests[./]test_store))'
---
