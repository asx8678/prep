**What will be done:**
1. `admin.py`: `handle` lets a request with the header `X-Debug: 1` through without the login check.
2. `tests/test_admin.py`: a new test for the header.

**Stays as it is:** the login check for every other request.
**How we know it works:** the new test fails today and passes after the change.
**Decided for you:** the header value must be exactly `1`.
**Risks:** none that cannot be undone.
**Left for you afterwards:** commit, push and deploy.

"ok" saves the brief. "full" shows the whole brief, which is in .briefs/draft.md. Or tell me what to change.
