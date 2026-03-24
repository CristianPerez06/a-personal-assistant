---
name: ripio-login
description: Automates the Ripio (auth.ripio.com) browser login flow using openclaw browser. Use when the user asks to log in to Ripio, navigate to their Ripio account, or start a Ripio browser session. Handles cookie consent, email/password entry, and 2FA (TOTP). Credentials and TOTP code must be provided by the user at runtime — never stored.
user-invocable: true
metadata: {"openclaw": {"emoji": "🦁", "requires": {"config": ["browser.enabled"]}}}
---

# Ripio Login

Automates login at `https://auth.ripio.com/#/login/` using `openclaw browser`.

## Flow

1. Ask the user for their **email** and **password**
2. Run the login script with those credentials
3. If 2FA is required (script exits with code `3`), ask the user for their current **TOTP code** and run the 2FA script
4. Report final page state

## Running the Script

### Step 1 — Login with email and password

Ask the user for their email and password, then run:

```bash
bash scripts/ripio-login.sh <email> <password>
```

- Exit code `0`: login succeeded (no 2FA required).
- Exit code `2`: credentials failed ("User could not authenticate").
- Exit code `3`: 2FA screen appeared — proceed to Step 2.

### Step 2 — Enter 2FA code (only if Step 1 exited with code 3)

Ask the user for their current 6-digit TOTP code, then run:

```bash
bash scripts/ripio-login.sh --2fa <totp_code>
```

- This assumes the browser is already on the 2FA screen from Step 1.
- Do **not** ask for the TOTP code upfront; only ask when 2FA is actually required.

## Post-Login

After a successful login, the browser session remains active. Continue using `openclaw browser snapshot/click/type` to interact with the authenticated session.

## Extending This Skill

To add steps after login (e.g. navigate to portfolio, place an order), append them to `scripts/ripio-login.sh` or create additional scripts in `scripts/` and document them here.
