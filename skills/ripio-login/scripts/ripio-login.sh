#!/usr/bin/env bash
# ripio-login.sh
# Automates the Ripio login flow via openclaw browser.
#
# Usage:
#   ripio-login.sh <email> <password>    — navigate, dismiss cookies, login
#   ripio-login.sh --2fa <totp_code>     — enter 2FA code on existing session
#
# Exit codes:
#   0 — success
#   1 — missing field / unexpected error
#   2 — wrong credentials
#   3 — 2FA screen detected (run again with --2fa)

set -e

RIPIO_URL="https://auth.ripio.com/#/login/"

enter_2fa() {
  local TOTP="$1"
  SNAP=$(openclaw browser snapshot)

  echo "[ripio-login] 2FA screen detected, entering code: $TOTP"
  DIGITS=("${TOTP:0:1}" "${TOTP:1:1}" "${TOTP:2:1}" "${TOTP:3:1}" "${TOTP:4:1}" "${TOTP:5:1}")
  REFS=($(echo "$SNAP" | grep -oP '(?<=textbox \[ref=)\w+(?=\])' | head -6))
  for i in 0 1 2 3 4 5; do
    openclaw browser type "${REFS[$i]}" "${DIGITS[$i]}"
  done

  SNAP=$(openclaw browser snapshot)
  SUBMIT_BTN=$(echo "$SNAP" | grep -oP '(?<=button "Ingresar" \[ref=)\w+(?=\])' | head -1)
  openclaw browser click "$SUBMIT_BTN"
  sleep 4

  SNAP=$(openclaw browser snapshot)
  echo "[ripio-login] Done. Final page:"
  echo "$SNAP" | grep "heading" | head -5
}

if [ "$1" = "--2fa" ]; then
  TOTP="${2:?Missing 2FA code}"
  enter_2fa "$TOTP"
  exit 0
fi

EMAIL="${1:?Usage: ripio-login.sh <email> <password>  OR  ripio-login.sh --2fa <totp_code>}"
PASSWORD="${2:?Missing password}"

echo "[ripio-login] Opening $RIPIO_URL"
openclaw browser navigate "$RIPIO_URL"
sleep 2

SNAP=$(openclaw browser snapshot)

# Dismiss cookie banner if present
COOKIE_BTN=$(echo "$SNAP" | grep -oP '(?<=button "Aceptar" \[ref=)\w+(?=\])' || true)
if [ -n "$COOKIE_BTN" ]; then
  echo "[ripio-login] Dismissing cookie banner (ref=$COOKIE_BTN)"
  openclaw browser click "$COOKIE_BTN"
  sleep 1
  SNAP=$(openclaw browser snapshot)
fi

# Fill email
EMAIL_REF=$(echo "$SNAP" | grep -oP '(?<=textbox "Mail" \[ref=)\w+(?=\])' || true)
if [ -z "$EMAIL_REF" ]; then
  echo "[ripio-login] ERROR: Could not find email field"
  exit 1
fi
echo "[ripio-login] Filling email (ref=$EMAIL_REF)"
openclaw browser type "$EMAIL_REF" "$EMAIL"

# Fill password
SNAP=$(openclaw browser snapshot)
PWD_REF=$(echo "$SNAP" | grep -oP '(?<=textbox "Contraseña" \[ref=)\w+(?=\])' || true)
if [ -z "$PWD_REF" ]; then
  echo "[ripio-login] ERROR: Could not find password field"
  exit 1
fi
echo "[ripio-login] Filling password (ref=$PWD_REF)"
openclaw browser evaluate --fn '(el) => { el.value = ""; el.dispatchEvent(new Event("input", {bubbles:true})); el.dispatchEvent(new Event("change", {bubbles:true})); }' --ref "$PWD_REF"
openclaw browser type "$PWD_REF" "$PASSWORD"

# Click Ingresar
SNAP=$(openclaw browser snapshot)
LOGIN_BTN=$(echo "$SNAP" | grep -oP '(?<=button "Ingresar" \[ref=)\w+(?=\])' | head -1)
echo "[ripio-login] Clicking Ingresar (ref=$LOGIN_BTN)"
openclaw browser click "$LOGIN_BTN"
sleep 3

# Check for auth error
SNAP=$(openclaw browser snapshot)
if echo "$SNAP" | grep -q "User could not authenticate"; then
  echo "[ripio-login] ERROR: Authentication failed — wrong email or password"
  exit 2
fi

# Check for 2FA
if echo "$SNAP" | grep -q "código de seguridad"; then
  echo "[ripio-login] 2FA required — ask the user for their TOTP code and re-run with --2fa"
  exit 3
fi

# No 2FA — login complete
echo "[ripio-login] Done. Final page:"
echo "$SNAP" | grep "heading" | head -5
