**What will be done:**
1. `greet.py`: `greeting` gets an optional `shout` argument; with it, the text comes back in capital letters.
2. `tests/test_greet.py`: two new tests, one for capitals and one that the usual greeting is unchanged.

**Stays as it is:** every call of `greeting` that exists today, and the README.
**How we know it works:** the new test fails today, because `greeting` does not know `shout`; after the change all three tests pass.
**Decided for you:** capitals come from Python's own `upper()`, since the request names no language.
**Risks:** none that cannot be undone; two files change.
**Left for you afterwards:** commit and push.

"ok" saves the brief. "full" shows the whole brief, which is in .briefs/draft.md. Or tell me what to change.
Say "keep a record" and I also keep a log line and a copy of this and later briefs in ~/.briefs/, where a later prep in any project can read them.

## Details
1. `greet.py:1-3` holds the only definition of `greeting`; nothing else in the project calls it.
2. `python3 -m unittest` prints "Ran 1 test" and "OK" today.
