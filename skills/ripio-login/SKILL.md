---
name: ripio-login
description: Automates the Ripio (auth.ripio.com) browser login flow using openclaw browser. Use when the user asks to log in to Ripio, navigate to their Ripio account, or start a Ripio browser session. Handles cookie consent, email/password entry, 2FA (TOTP), and magic link email verification. Credentials are read from RIPIO_EMAIL and RIPIO_PASSWORD env vars (falls back to asking the user). TOTP code and magic link are requested at runtime when needed.
user-invocable: true
metadata:
  {
    "openclaw":
      { "emoji": "🦁", "requires": { "config": ["browser.enabled"] } },
  }
---

# Ripio Login

Automates login at `https://auth.ripio.com/#/login/` using `openclaw browser`.

## Flow

1. Read credentials from the **`RIPIO_EMAIL`** and **`RIPIO_PASSWORD`** environment variables and run the login script. If either variable is missing, ask the user to provide it.
2. If 2FA is required (script exits with code `3`), ask the user for their current **TOTP code** and run the 2FA script.
3. If magic link verification is required (script exits with code `4`), ask the user to check their email and send the magic link URL. Open the link in the headless browser.
4. Report final page state.

## Running the Script

### Step 1 — Login with email and password

First, check if `RIPIO_EMAIL` and `RIPIO_PASSWORD` environment variables are set:

```bash
echo "RIPIO_EMAIL=${RIPIO_EMAIL:-NOT_SET}" && echo "RIPIO_PASSWORD=${RIPIO_PASSWORD:-NOT_SET}"
```

If both are set, pass them as arguments:

```bash
bash scripts/ripio-login.sh "$RIPIO_EMAIL" "$RIPIO_PASSWORD"
```

If either variable is missing, ask the user for the missing value(s) and pass them directly:

```bash
bash scripts/ripio-login.sh <email> <password>
```

- Exit code `0`: login succeeded (no 2FA required).
- Exit code `2`: credentials failed ("User could not authenticate").
- Exit code `3`: 2FA screen appeared — proceed to Step 2.
- Exit code `4`: magic link verification required — proceed to Step 3.

### Step 2 — Enter 2FA code (only if Step 1 exited with code 3)

Ask the user for their current 6-digit TOTP code, then run:

```bash
bash scripts/ripio-login.sh --2fa <totp_code>
```

- This assumes the browser is already on the 2FA screen from Step 1.
- Do **not** ask for the TOTP code upfront; only ask when 2FA is actually required.
- Exit code `0`: Ripio redirected to the app — login complete.
- Exit code `4`: Ripio showed the magic-link email screen after 2FA — proceed to Step 3 (same as after Step 1).
- Exit code `5`: unexpected state after 2FA (still on auth without a known signal) — report per Failure Handling.

### Step 3 — Magic link verification (only if Step 1 or Step 2 exited with code 4)

Ask the user to check their email for the Ripio verification link. Tell them to send **only the token** (the UUID at the end of the URL, e.g. `5b91a6ba-dfb9-466f-86f4-645cd6c344eb`), **not the full URL**. This avoids Telegram's link preview consuming the single-use link.

Then run the script with just the token:

```bash
bash scripts/ripio-login.sh --magic-link <token>
```

- Do **not** ask for the token upfront; only ask when the magic link step is actually required.
- The script constructs the full URL and navigates to it. Report the output to the user.

## Failure Handling

**Do not attempt to fix, work around, or retry failures autonomously.** If any
script step fails, stop immediately and report the following to the user:

- The exact command that was run
- The exit code
- The full stderr/stdout output (untruncated)
- The current page URL and a fresh `openclaw browser snapshot`, if a browser
  is involved

Do not edit the script. Do not try alternate selectors, alternate commands,
direct browser launches, or other "creative" workarounds. Do not retry. Do
not change the OpenClaw config. The user will investigate and direct any fix.

## Post-Login

After a successful login via magic link, the dashboard modal (if present) is **automatically closed**. The script detects the modal by its:

- Class name starting with `modalClose`
- Data-testid containing `dashboard_modal_bridge_news_close_button`

The browser session then remains active and ready for further interaction. Continue using `openclaw browser snapshot/click/type` to interact with the authenticated session.

## Extending This Skill

To add steps after login (e.g. navigate to portfolio, place an order), append them to `scripts/ripio-login.sh` or create additional scripts in `scripts/` and document them here.
