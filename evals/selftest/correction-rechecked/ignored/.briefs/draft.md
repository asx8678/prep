# Give greeting an optional shout argument

Type: add-shout-argument | Date: 2026-11-12-000000 | Commit: 0a1b2c3 | Status: ready

## Goal
`greeting` can return its text in capital letters.
Example: `greeting("Ada", shout=True)` returns `HELLO, ADA.`

## Changes
1. `greet.py:1`: the signature becomes `greeting(name, shout=False)`. Check: Proof 1.

## Decisions
- The argument is called `loud`, where the request said shout (by: person).

## Proof
1. `python3 -m unittest` fails today with "unexpected keyword argument 'shout'" and prints "OK" after the change.
