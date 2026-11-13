# Give greeting an optional loud argument

Type: add-loud-argument | Date: 2026-11-12-000000 | Commit: 0a1b2c3 | Status: ready

## Goal
`greeting` can return its text in capital letters.
Example: `greeting("Ada", loud=True)` returns `HELLO, ADA.`

## Changes
1. `greet.py:1`: the signature becomes `greeting(name, loud=False)`. Check: Proof 1.

## Decisions
- The argument is called `loud`, where the request said shout (by: person).

## Proof
1. `python3 -m unittest` fails today with "unexpected keyword argument 'loud'" and prints "OK" after the change.
