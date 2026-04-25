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

# Fill an input field reliably on React-controlled forms.
#
# Clear via the *native* HTMLInputElement value setter (accessed through
# the prototype descriptor), not a plain `el.value = ""`. React monkey-patches
# the value setter on input elements to track changes; assigning to `.value`
# directly bypasses that tracker, so React keeps its stale internal state and
# re-renders the old value on the next tick. Subsequent `type` keystrokes then
# land in what React considers an already-full single-char input (e.g. OTP
# boxes) and get silently dropped.
#
# Calling the native setter via `Object.getOwnPropertyDescriptor(...).set.call`
# triggers React's tracker correctly, so the input/change events that follow
# update React's synthetic state, and the keystrokes that follow are accepted.
fill_input() {
  local ref="$1"
  local value="$2"
  openclaw browser evaluate --fn '(el) => { const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set; setter.call(el, ""); el.dispatchEvent(new Event("input", {bubbles:true})); el.dispatchEvent(new Event("change", {bubbles:true})); }' --ref "$ref"
  openclaw browser type "$ref" "$value"
}

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
  
  # Close dashboard bridge-news modal if present.
  # Find by id, verify by data-testid — `openclaw browser snapshot` outputs an
  # accessibility tree that does not include CSS classes or data-testid
  # attributes, so grepping the snapshot for those is unreliable.
  sleep 2
  CLOSE_RESULT=$(openclaw browser evaluate --fn '() => {
    const btn = document.getElementById("dashboard_modal_bridge_news_close_button");
    if (!btn) return "not_present";
    if (btn.getAttribute("data-testid") !== "dashboard_modal_bridge_news_close_button") return "wrong_testid";
    btn.click();
    return "closed";
  }')
  echo "[ripio-login] Modal-close result: $CLOSE_RESULT"
  case "$CLOSE_RESULT" in
    '"closed"'|'closed') echo "[ripio-login] Dashboard modal closed"; sleep 1 ;;
    '"not_present"'|'not_present') echo "[ripio-login] No dashboard modal (already closed or never appeared)" ;;
    *) echo "[ripio-login] WARNING: unexpected modal-close result: $CLOSE_RESULT" ;;
  esac
  
  exit 0
fi

# --- 2FA-only mode ---
if [ "$1" = "--2fa" ]; then
  TOTP="${2:?Missing 2FA code}"
  if [ "${#TOTP}" != "6" ] || ! [[ "$TOTP" =~ ^[0-9]{6}$ ]]; then
    echo "[ripio-login] ERROR: 2FA code must be exactly 6 digits"
    exit 1
  fi

  # Fill all 6 OTP fields in a single evaluate call. Doing one round-trip
  # per digit (≈12 round-trips with the clear+type pattern) takes ~25-30s,
  # which exceeds the 30-second TOTP validity window — codes expire before
  # submit. One evaluate keeps the whole fill under a second.
  #
  # Locator priority:
  #   1. inputs with autocomplete="one-time-code" (standardized OTP hint)
  #   2. fallback: text/tel/number inputs with maxLength === 1
  echo "[ripio-login] Filling 2FA code in one shot"
  FILL_RESULT=$(openclaw browser evaluate --fn "() => {
    const digits = '$TOTP';
    let inputs = Array.from(document.querySelectorAll('input[autocomplete*=\"one-time-code\"]'));
    if (inputs.length < 6) {
      inputs = Array.from(document.querySelectorAll('input')).filter(i =>
        (i.type === 'text' || i.type === 'tel' || i.type === 'number') && i.maxLength === 1
      );
    }
    if (inputs.length < 6) return 'wrong_input_count:' + inputs.length;
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
    for (let i = 0; i < 6; i++) {
      setter.call(inputs[i], digits[i]);
      inputs[i].dispatchEvent(new Event('input', { bubbles: true }));
      inputs[i].dispatchEvent(new Event('change', { bubbles: true }));
    }
    return 'ok';
  }")
  echo "[ripio-login] Fill result: $FILL_RESULT"
  case "$FILL_RESULT" in
    '\"ok\"'|'"ok"'|'ok') ;;
    *) echo "[ripio-login] ERROR: 2FA fill failed: $FILL_RESULT"; exit 1 ;;
  esac

  # Click Ingresar immediately — every second between fill and submit
  # eats into the TOTP window.
  SNAP=$(openclaw browser snapshot)
  SUBMIT_BTN=$(echo "$SNAP" | grep -oP '(?<=button "Ingresar" \[ref=)\w+(?=\])' | head -1)
  if [ -z "$SUBMIT_BTN" ]; then
    echo "[ripio-login] ERROR: could not find Ingresar button on 2FA screen"
    exit 1
  fi
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
fill_input "$EMAIL_REF" "$EMAIL"

# Fill password
SNAP=$(openclaw browser snapshot)
PWD_REF=$(echo "$SNAP" | grep -oP '(?<=textbox "Contraseña" \[ref=)\w+(?=\])' || true)
if [ -z "$PWD_REF" ]; then
  echo "[ripio-login] ERROR: Could not find password field"
  exit 1
fi
echo "[ripio-login] Filling password (ref=$PWD_REF)"
fill_input "$PWD_REF" "$PASSWORD"

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