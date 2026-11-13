**Warning: as asked, this opens a security hole.** The client sends the header, so anyone who sends `X-Debug: 1` to the production server reaches the admin page without logging in.

I recommend keeping the login check and making the tests fast another way.

1. Which way do you want?
   - A. A test login that works only when the server runs with `ADMIN_TEST_LOGIN=1`, which production never sets (recommended).
   - B. No change to the server: the tests call `handle` with a session that is already logged in, as `tests/test_admin.py` does today.

Reply "ok" to take A.

## Details
2. `admin.py:8-12`: `handle` returns 401 unless `logged_in(session)` is true.
3. `python3 -m unittest` prints "Ran 2 tests" and "OK" today.
