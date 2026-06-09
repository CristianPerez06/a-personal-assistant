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
#
# Selector strategy: DOM via `openclaw browser evaluate`, using Ripio's stable
# element ids and data-testids (login_email_input, login_password_input,
# login_submit_button, mfa_method_select, mfa_method_submit_button,
# mfa_otp_input_1..6, mfa_submit_button). The previous version parsed
# accessibility snapshots with regex; that broke when Ripio's renderer added
# attribute markers like `[active]` between the element name and `[ref=...]`
# in the snapshot output.

set -e

# Ensure Chromium is running. `browser start` is a no-op if already up;
# without it the agent's planning step can see status.running=false between
# script runs and bail with a misleading "browser is not running" reply.
openclaw browser start >/dev/null

# Escape a string for embedding inside a single-quoted JS string literal.
# Handles backslash and single-quote — sufficient for typed values like
# emails and passwords (no control chars expected).
js_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\'/\\\'}"
  printf "%s" "$s"
}

# Fill an input by element id. Uses the native HTMLInputElement value setter
# (via prototype descriptor): React tracks input changes through that setter,
# so a plain `el.value = X` bypasses the tracker and React keeps its stale
# internal state, dropping subsequent input events. Clear, then set, dispatching
# input/change events so React's synthetic state catches up.
fill_by_id() {
  local id="$1"
  local value
  value=$(js_escape "$2")
  local result
  result=$(openclaw browser evaluate --fn "() => {
    const el = document.getElementById('$id');
    if (!el) return 'not_found';
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
    setter.call(el, '');
    el.dispatchEvent(new Event('input', { bubbles: true }));
    setter.call(el, '$value');
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    return 'ok';
  }")
  case "$result" in
    '"ok"'|'ok') return 0 ;;
    *) echo "fill_by_id($id): $result" >&2; return 1 ;;
  esac
}

# Click an element by id. Verifies element exists and isn't disabled before clicking.
click_by_id() {
  local id="$1"
  local result
  result=$(openclaw browser evaluate --fn "() => {
    const el = document.getElementById('$id');
    if (!el) return 'not_found';
    if (el.hasAttribute('disabled')) return 'disabled';
    el.click();
    return 'clicked';
  }")
  case "$result" in
    '"clicked"'|'clicked') return 0 ;;
    *) echo "click_by_id($id): $result" >&2; return 1 ;;
  esac
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

  # Fill all 6 OTP fields AND click submit in a single evaluate call.
  # Two reasons to bundle:
  #   - Each openclaw round-trip is 1-3s on a constrained VM; combining
  #     fill+click saves one round-trip.
  #   - Every second between fill and submit eats into the 30-60s TOTP
  #     window. Doing it atomically inside one JS execution is the tightest
  #     we can get.
  SUBMIT_RESULT=$(openclaw browser evaluate --fn "() => {
    const digits = '$TOTP';
    for (let i = 1; i <= 6; i++) {
      if (!document.getElementById('mfa_otp_input_' + i)) {
        return 'missing_input:mfa_otp_input_' + i;
      }
    }
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
    for (let i = 1; i <= 6; i++) {
      const el = document.getElementById('mfa_otp_input_' + i);
      setter.call(el, digits[i-1]);
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
    }
    const btn = document.getElementById('mfa_submit_button');
    if (!btn) return 'submit_not_found';
    if (btn.hasAttribute('disabled')) return 'submit_disabled';
    btn.click();
    return 'submitted';
  }")
  case "$SUBMIT_RESULT" in
    '"submitted"'|'submitted') ;;
    *missing_input*) echo "2FA screen not loaded — OTP inputs not found ($SUBMIT_RESULT)." >&2; exit 1 ;;
    *submit_disabled*) echo "Submit button stayed disabled after fill — code rejected at the input level ($SUBMIT_RESULT)." >&2; exit 1 ;;
    *) echo "2FA fill+submit failed: $SUBMIT_RESULT" >&2; exit 1 ;;
  esac

  # Poll the URL — cheap (~50-100ms per call) compared to a full accessibility
  # snapshot. Only fall back to a snapshot for the final state diagnosis if
  # the URL never advances to app.ripio.com.
  for _attempt in 1 2 3 4 5 6 7 8 9 10; do
    sleep 1
    CURR_URL=$(openclaw browser evaluate --fn '() => window.location.href' | tr -d '"')
    case "$CURR_URL" in
      https://app.ripio.com*)
        echo "Signed in."
        exit 0
        ;;
    esac
  done

  # URL never advanced — diagnose via snapshot (single, expensive call done once).
  SNAP=$(openclaw browser snapshot)
  if echo "$SNAP" | grep -qi "Te enviamos un mail"; then
    echo "Valid credentials. Magic link sent to your email — paste the token to continue."
    exit 4
  fi
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

# Fill email
if ! fill_by_id "login_email_input" "$EMAIL"; then
  echo "Couldn't fill the email field on the login page." >&2
  exit 1
fi

# Fill password
if ! fill_by_id "login_password_input" "$PASSWORD"; then
  echo "Couldn't fill the password field on the login page." >&2
  exit 1
fi

# Click Ingresar
if ! click_by_id "login_submit_button"; then
  echo "Couldn't click the submit button on the login page." >&2
  exit 1
fi
sleep 3

# Check for auth error. Detected via snapshot text — Ripio doesn't expose
# a stable testid on the error toast/message that we've located yet.
SNAP=$(openclaw browser snapshot)
if echo "$SNAP" | grep -q "User could not authenticate"; then
  echo "Invalid email or password."
  exit 2
fi

# MFA method picker: Ripio now shows a modal asking which 2FA method to use
# before the OTP screen. #mfa_method_select is the list container; the actual
# TOTP option is a radio input with a per-device id like
# `mfa_method_<base64>`. We locate it by the label text matching "App de
# códigos externa" (TOTP), falling back to the only input if there's just one.
SELECT_RESULT=$(openclaw browser evaluate --fn '() => {
  const container = document.getElementById("mfa_method_select");
  if (!container) return "absent";
  const inputs = Array.from(container.querySelectorAll("input"));
  if (!inputs.length) return "no_inputs";
  let target = null;
  for (const inp of inputs) {
    const label = container.querySelector(`label[for="${inp.id}"]`) || inp.closest("label");
    const text = (label?.textContent || "").toLowerCase();
    if (text.includes("códigos externa") || text.includes("authenticator")) {
      target = inp;
      break;
    }
  }
  if (!target && inputs.length === 1) target = inputs[0];
  if (!target) return "no_match";
  target.click();
  return "selected";
}' | tr -d '"')
case "$SELECT_RESULT" in
  selected) ;;
  absent) ;;
  *) echo "MFA method picker present but couldn'\''t pick option: $SELECT_RESULT" >&2; exit 5 ;;
esac

# Submit method choice (separate evaluate so React can re-render between the
# radio click and the disabled-check on the submit button).
if [ "$SELECT_RESULT" = "selected" ]; then
  sleep 1
  SUBMIT_METHOD=$(openclaw browser evaluate --fn '() => {
    const submit = document.getElementById("mfa_method_submit_button");
    if (!submit) return "submit_not_found";
    if (submit.hasAttribute("disabled")) return "submit_disabled";
    submit.click();
    return "submitted";
  }' | tr -d '"')
  case "$SUBMIT_METHOD" in
    submitted) sleep 2 ;;
    *) echo "MFA method submit failed: $SUBMIT_METHOD" >&2; exit 5 ;;
  esac
fi

# 2FA detection: look for the 6 OTP inputs by their stable ids
# (mfa_otp_input_1 .. mfa_otp_input_6). Same locator strategy as the
# --2fa fill mode. Text grep on the snapshot is fragile — Ripio's 2FA screen
# copy can change ("código de seguridad" was matched in the past, but the
# page now apparently renders different text and the grep misses).
OTP_PRESENT=$(openclaw browser evaluate --fn '() => {
  for (let i = 1; i <= 6; i++) {
    if (!document.getElementById("mfa_otp_input_" + i)) return "no";
  }
  return "yes";
}' | tr -d '"')
if [ "$OTP_PRESENT" = "yes" ]; then
  echo "Valid credentials. 2FA code required."
  exit 3
fi

# Magic link step — Ripio sends an email with a verification link.
# Detected via snapshot text (same caveat as auth-error above).
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
