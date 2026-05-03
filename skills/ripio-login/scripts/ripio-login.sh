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
#   0 — success (browser landed on app.ripio.com)
#   2 — bad credentials
#   3 — 2FA required (run again with --2fa <code>)
#   4 — magic link required (run again with --magic-link <url>)
#   5 — unknown post-submit state (still on auth.ripio.com, no signal matched)
#
# After --2fa: same outcomes as post password — 0 (app), 4 (magic link), 5 (unknown).

set -e

# Ensure Chromium is running. `browser start` is a no-op if already up;
# without it the agent's planning step can see status.running=false between
# script runs and bail with a misleading "browser is not running" reply.
openclaw browser start >/dev/null

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
  echo "Opening magic link…"
  openclaw browser navigate "$LINK" >/dev/null

  # Wait for redirects to complete — poll URL until it stabilizes.
  PREV_URL=""
  for i in 1 2 3 4 5 6; do
    sleep 3
    CURR_URL=$(openclaw browser evaluate --fn '() => window.location.href' 2>/dev/null)
    if [ "$CURR_URL" = "$PREV_URL" ]; then
      break
    fi
    PREV_URL="$CURR_URL"
  done

  # Close dashboard bridge-news modal if present (silent — internal detail).
  # Find by id, verify by data-testid — `openclaw browser snapshot` outputs an
  # accessibility tree that does not include CSS classes or data-testid
  # attributes, so grepping the snapshot for those is unreliable.
  sleep 2
  openclaw browser evaluate --fn '() => {
    const btn = document.getElementById("dashboard_modal_bridge_news_close_button");
    if (btn && btn.getAttribute("data-testid") === "dashboard_modal_bridge_news_close_button") {
      btn.click();
    }
  }' >/dev/null 2>&1 || true

  echo "Signed in."
  exit 0
fi

# --- 2FA-only mode ---
if [ "$1" = "--2fa" ]; then
  TOTP="${2:?Missing 2FA code}"
  if [ "${#TOTP}" != "6" ] || ! [[ "$TOTP" =~ ^[0-9]{6}$ ]]; then
    echo "2FA code must be exactly 6 digits."
    exit 1
  fi

  echo "Submitting 2FA code…"

  # Fill all 6 OTP fields in a single evaluate call. Doing one round-trip
  # per digit (≈12 round-trips with the clear+type pattern) takes ~25-30s,
  # which exceeds the 30-second TOTP validity window — codes expire before
  # submit. One evaluate keeps the whole fill under a second.
  FILL_RESULT=$(openclaw browser evaluate --fn "() => {
    const digits = '$TOTP';
    const inputs = [];
    for (let i = 1; i <= 6; i++) {
      const el = document.getElementById('login_otp_input_' + i);
      if (!el) return 'missing_input:login_otp_input_' + i;
      inputs.push(el);
    }
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
    for (let i = 0; i < 6; i++) {
      setter.call(inputs[i], digits[i]);
      inputs[i].dispatchEvent(new Event('input', { bubbles: true }));
      inputs[i].dispatchEvent(new Event('change', { bubbles: true }));
    }
    return 'ok';
  }")
  case "$FILL_RESULT" in
    '\"ok\"'|'"ok"'|'ok') ;;
    *) echo "2FA screen not loaded — OTP inputs not found ($FILL_RESULT)." >&2; exit 1 ;;
  esac

  # Click Ingresar immediately — every second between fill and submit
  # eats into the TOTP window.
  SNAP=$(openclaw browser snapshot)
  SUBMIT_BTN=$(echo "$SNAP" | grep -oP '(?<=button "Ingresar" \[ref=)\w+(?=\])' | head -1)
  if [ -z "$SUBMIT_BTN" ]; then
    echo "Couldn't find the submit button on the 2FA screen." >&2
    exit 1
  fi
  openclaw browser click "$SUBMIT_BTN" >/dev/null

  # Post-2FA Ripio may redirect to app, or show the magic-link screen (same copy
  # as after password). Do not exit 0 until we confirm app — otherwise downstream
  # skills think we're logged in while still on auth.
  for _attempt in 1 2 3 4 5; do
    sleep 2
    SNAP=$(openclaw browser snapshot)
    if echo "$SNAP" | grep -qi "Te enviamos un mail"; then
      echo "Valid credentials. Magic link sent to your email — paste the token to continue."
      exit 4
    fi
    CURR_URL=$(openclaw browser evaluate --fn '() => window.location.href' | tr -d '"')
    case "$CURR_URL" in
      https://app.ripio.com*)
        echo "Signed in."
        exit 0
        ;;
    esac
  done

  SNAP=$(openclaw browser snapshot)
  if echo "$SNAP" | grep -qi "Te enviamos un mail"; then
    echo "Valid credentials. Magic link sent to your email — paste the token to continue."
    exit 4
  fi
  CURR_URL=$(openclaw browser evaluate --fn '() => window.location.href' | tr -d '"')
  case "$CURR_URL" in
    https://app.ripio.com*)
      echo "Signed in."
      exit 0
      ;;
  esac
  echo "2FA submitted but sign-in did not complete — still on auth or unknown state." >&2
  echo "$SNAP" | grep "heading" | head -10 >&2
  exit 5
fi

EMAIL="${1:?Usage: ripio-login.sh <email> <password>}"
PASSWORD="${2:?Missing password}"

RIPIO_URL="https://auth.ripio.com/#/login/"

echo "Signing in…"
openclaw browser navigate "$RIPIO_URL" >/dev/null
sleep 2

# Snapshot to get current refs
SNAP=$(openclaw browser snapshot)

# Dismiss cookie banner if present (silent — internal detail).
COOKIE_BTN=$(echo "$SNAP" | grep -oP '(?<=button "Aceptar" \[ref=)\w+(?=\])' || true)
if [ -n "$COOKIE_BTN" ]; then
  openclaw browser click "$COOKIE_BTN" >/dev/null
  sleep 1
  SNAP=$(openclaw browser snapshot)
fi

# Fill email
EMAIL_REF=$(echo "$SNAP" | grep -oP '(?<=textbox "Mail" \[ref=)\w+(?=\])' || true)
if [ -z "$EMAIL_REF" ]; then
  echo "Couldn't find the email field on the login page." >&2
  exit 1
fi
fill_input "$EMAIL_REF" "$EMAIL" >/dev/null

# Fill password
SNAP=$(openclaw browser snapshot)
PWD_REF=$(echo "$SNAP" | grep -oP '(?<=textbox "Contraseña" \[ref=)\w+(?=\])' || true)
if [ -z "$PWD_REF" ]; then
  echo "Couldn't find the password field on the login page." >&2
  exit 1
fi
fill_input "$PWD_REF" "$PASSWORD" >/dev/null

# Click Ingresar
SNAP=$(openclaw browser snapshot)
LOGIN_BTN=$(echo "$SNAP" | grep -oP '(?<=button "Ingresar" \[ref=)\w+(?=\])' | head -1)
openclaw browser click "$LOGIN_BTN" >/dev/null
sleep 3

# Check for auth error
SNAP=$(openclaw browser snapshot)
if echo "$SNAP" | grep -q "User could not authenticate"; then
  echo "Invalid email or password."
  exit 2
fi

# 2FA detection: look for the 6 OTP inputs by their stable ids
# (login_otp_input_1 .. login_otp_input_6). Same locator strategy as the
# --2fa fill mode. Text grep on the snapshot is fragile — Ripio's 2FA screen
# copy can change ("código de seguridad" was matched in the past, but the
# page now apparently renders different text and the grep misses).
OTP_PRESENT=$(openclaw browser evaluate --fn '() => {
  for (let i = 1; i <= 6; i++) {
    if (!document.getElementById("login_otp_input_" + i)) return "no";
  }
  return "yes";
}' | tr -d '"')
if [ "$OTP_PRESENT" = "yes" ]; then
  echo "Valid credentials. 2FA code required."
  exit 3
fi

# Magic link step — Ripio sends an email with a verification link
if echo "$SNAP" | grep -qi "Te enviamos un mail"; then
  echo "Valid credentials. Magic link sent to your email — paste the token to continue."
  exit 4
fi

# Success requires the URL to have advanced off auth.ripio.com. Anything else
# is an unknown state — DO NOT return 0, that masks a stuck login.
CURR_URL=$(openclaw browser evaluate --fn '() => window.location.href' | tr -d '"')
case "$CURR_URL" in
  https://app.ripio.com*)
    echo "Signed in."
    exit 0
    ;;
  *)
    echo "Sign-in didn't complete — page is in an unexpected state." >&2
    echo "$SNAP" | grep "heading" | head -10 >&2
    exit 5
    ;;
esac