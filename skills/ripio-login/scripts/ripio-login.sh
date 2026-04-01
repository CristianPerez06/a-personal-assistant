#!/usr/bin/env bash
# ripio-login.sh
# Automates the Ripio login flow via openclaw browser.
#
# Usage:
#   Step 1 — login:       ripio-login.sh <email> <password>
#   Step 2 — 2FA submit:  ripio-login.sh --2fa <totp_code>
#   Step 3 — magic link:  ripio-login.sh --magic-link <url>
#
# Exit codes:
#   0 — success
#   2 — bad credentials
#   3 — 2FA required (run again with --2fa <code>)
#   4 — magic link required (run again with --magic-link <url>)

set -e

# --- Magic link mode ---
if [ "$1" = "--magic-link" ]; then
  TOKEN="${2:?Missing magic link token}"
  MAGIC_LINK_BASE="https://auth.ripio.com/authentication/complete-login"
  LINK="${MAGIC_LINK_BASE}/${TOKEN}/"
  echo "[ripio-login] Token received: $TOKEN"
  echo "[ripio-login] Full URL: $LINK"
  echo "[ripio-login] Current page URL before navigating:"
  openclaw browser evaluate --fn '() => window.location.href'
  echo "[ripio-login] Opening magic link in headless browser"
  openclaw browser navigate "$LINK"

  # Wait for redirects to complete — poll URL until it stabilizes
  PREV_URL=""
  for i in 1 2 3 4 5 6; do
    sleep 3
    CURR_URL=$(openclaw browser evaluate --fn '() => window.location.href')
    echo "[ripio-login] URL after ${i}x3s: $CURR_URL"
    if [ "$CURR_URL" = "$PREV_URL" ]; then
      echo "[ripio-login] URL stabilized"
      break
    fi
    PREV_URL="$CURR_URL"
  done

  SNAP=$(openclaw browser snapshot)
  echo "[ripio-login] Done. Full page state after magic link:"
  echo "$SNAP"
  exit 0
fi

# --- 2FA-only mode ---
if [ "$1" = "--2fa" ]; then
  TOTP="${2:?Missing 2FA code}"
  SNAP=$(openclaw browser snapshot)
  DIGITS=("${TOTP:0:1}" "${TOTP:1:1}" "${TOTP:2:1}" "${TOTP:3:1}" "${TOTP:4:1}" "${TOTP:5:1}")
  REFS=($(echo "$SNAP" | grep -oP 'textbox(?:\s+\[\w+\])*\s+\[ref=\K\w+(?=\])' | head -6))
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
  exit 0
fi

EMAIL="${1:?Usage: ripio-login.sh <email> <password>}"
PASSWORD="${2:?Missing password}"

RIPIO_URL="https://auth.ripio.com/#/login/"

echo "[ripio-login] Opening $RIPIO_URL"
openclaw browser navigate "$RIPIO_URL"
sleep 2

# Snapshot to get current refs
SNAP=$(openclaw browser snapshot)

# Dismiss cookie banner if present (button "Aceptar")
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

# 2FA step
if echo "$SNAP" | grep -q "código de seguridad"; then
  echo "[ripio-login] 2FA screen detected"
  exit 3
fi

# Magic link step — Ripio sends an email with a verification link
if echo "$SNAP" | grep -qi "Te enviamos un mail"; then
  echo "[ripio-login] Magic link verification detected — check your email and send the link"
  exit 4
fi

# Final state
SNAP=$(openclaw browser snapshot)
echo "[ripio-login] Done. Final page:"
echo "$SNAP" | grep "heading" | head -5
