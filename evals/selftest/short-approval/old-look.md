Here is the brief. Please check it and tell me what to correct.

# Give greeting an optional shout argument

Type: add-shout-argument | Date: 2026-11-12-000000 | Commit: 0a1b2c3 | Status: ready

## Goal
`greeting` can return its text in capital letters, for the banner page.
Example: `greeting("Ada", shout=True)` returns `HELLO, ADA.`

## Current state
- `greet.py:1-3`: `greeting(name)` returns "Hello, " + name + "."
- `tests/test_greet.py:6-8`: one test, `python3 -m unittest` prints "Ran 1 test" and "OK".

## Example to follow
No other function here has an optional argument; follow PEP 8 for the default.

## Approach
Add the argument with a default of False, so every caller today keeps its result.
Lost: a second function `shout_greeting` (two names for one thing).

## Changes
1. `greet.py:1`: the signature becomes `greeting(name, shout=False)`. Check: Proof 1.
2. `greet.py:3`: return the text in capitals when `shout` is true. Check: Proof 1.
3. `tests/test_greet.py`: a test for `shout=True` and one that the default is unchanged. Check: Proof 2.

## Decisions
- The argument is named `shout`, as asked (by: person).
- Capitals come from `str.upper()` (assumed: the request names no locale).

## Out of scope
- The README, and any caller outside this folder.

## Risks and blockers
- None that cannot be undone: two files change.

## Proof
For the implementing session:
1. `python3 -m unittest tests.test_greet` fails today with the new test: `TypeError: greeting() got an
   unexpected keyword argument 'shout'`. Today: exactly this.
2. After the change `python3 -m unittest` prints "Ran 3 tests" and "OK". Today: "Ran 1 test", "OK".

## Sources
- https://docs.python.org/3/library/stdtypes.html#str.upper

## Open questions
None.

## For the implementing session
Follow this brief. If something in it is wrong or impossible, stop and
say so instead of improvising. Check secrets by name only; never print a
value. Read a live system only where Decisions say the person allowed it.
Never run `git stash`, `checkout`, `restore`, `reset` or `clean`. Do not
commit, push, deploy, apply or migrate, or change a live system or
infrastructure state in any other way, unless the person asks for it in this
conversation after seeing what will change. When finished, tell the person
in one line what this brief got wrong or left out.

Keep a record of this task on this computer? Later preps in any project may read it.
- A. No.
- B. Yes. Add one line to the log and keep a copy of the brief.
- C. Yes, and also check whether I asked for something like this before, so that a repeat can get a dedicated skill.

I recommend B. "ok" accepts the brief and my recommendation.
