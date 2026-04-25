#!/usr/bin/env bash
# ripio-buy.sh
# Buys the configured asset on Ripio using the full available fiat balance.
# Assumes the browser is already logged into Ripio (run the ripio-login skill first,
# or use the ripio-dca orchestrator skill to do login + buy in one go).
#
# Usage:
#   Buy:      ripio-buy.sh    (reads RIPIO_DCA_ASSET_ORIGIN and RIPIO_DCA_ASSET_TARGET)
#   Inspect:  ripio-buy.sh --inspect
#
# Exit codes:
#   0 — buy completed
#   1 — generic / selector not found
#   2 — insufficient fiat balance
#   3 — buy rejected by Ripio
#   4 — not logged in

set -e

# --- Configuration ---
RIPIO_APP_HOST="https://app.ripio.com"

# Helper: print a log line
log() { echo "[ripio-buy] $*"; }

# Helper: confirm we're on the authenticated Ripio app (post-login dashboard).
# After login, Ripio lands the user on https://app.ripio.com/... — if the
# current URL doesn't start with that, the session isn't ready and we abort.
#
# `openclaw browser evaluate` returns its result JSON-encoded, so a string
# value comes back wrapped in literal double quotes (e.g. "https://app.ripio.com/").
# We strip surrounding quotes before doing the prefix check.
ensure_logged_in() {
  local url
  url=$(openclaw browser evaluate --fn '() => window.location.href')
  url="${url%\"}"
  url="${url#\"}"
  if ! echo "$url" | grep -q "^${RIPIO_APP_HOST}"; then
    log "ERROR: expected to be on ${RIPIO_APP_HOST} but current URL is: $url"
    log "Run the ripio-login skill first."
    exit 4
  fi
  log "Logged-in URL confirmed: $url"
}

# --- Inspect mode ---
if [ "$1" = "--inspect" ]; then
  log "Inspect mode: dumping current page (no navigation)"
  ensure_logged_in
  log "Full snapshot:"
  openclaw browser snapshot
  exit 0
fi

ASSET_ORIGIN="${RIPIO_DCA_ASSET_ORIGIN:?Missing env var RIPIO_DCA_ASSET_ORIGIN (e.g. ARS)}"
ASSET_TARGET="${RIPIO_DCA_ASSET_TARGET:?Missing env var RIPIO_DCA_ASSET_TARGET (e.g. BTC)}"
ASSET_ORIGIN_UPPER=$(echo "$ASSET_ORIGIN" | tr '[:lower:]' '[:upper:]')
ASSET_ORIGIN_LOWER=$(echo "$ASSET_ORIGIN" | tr '[:upper:]' '[:lower:]')
ASSET_TARGET_UPPER=$(echo "$ASSET_TARGET" | tr '[:lower:]' '[:upper:]')

# --- Stage 1: confirm we're on the authenticated dashboard ---
log "Stage 1: confirming authenticated session"
ensure_logged_in

# --- Stage 2: confirm dashboard is rendered, then navigate to /swap ---
# Headless Chromium has trouble interacting with the dashboard's Buy button
# (clicks were silently no-ops). Instead, verify the dashboard is fully
# rendered by checking for the topnav welcome element, then navigate directly
# to the swap URL — which is what clicking Buy would have done anyway.
log "Stage 2: verifying dashboard is rendered (topnav_welcome)"
DASHBOARD_RESULT=$(openclaw browser evaluate --fn '() => {
  const el = document.getElementById("topnav_welcome");
  if (!el) return "not_found:no_id";
  if (el.getAttribute("data-testid") !== "topnav_welcome") return "not_found:wrong_testid";
  if (!/welcome/i.test((el.textContent || "").trim())) return "not_found:no_welcome_text";
  return "ok";
}')
log "Dashboard check result: $DASHBOARD_RESULT"
case "$DASHBOARD_RESULT" in
  '"ok"'|'ok') log "Dashboard confirmed" ;;
  *) log "ERROR: dashboard not rendered: $DASHBOARD_RESULT"; exit 1 ;;
esac

log "Stage 2: navigating to ${RIPIO_APP_HOST}/swap"
openclaw browser navigate "${RIPIO_APP_HOST}/swap"
sleep 2

# --- Stage 3: verify navigation to the swap page ---
# evaluate returns a JSON-encoded string; strip the surrounding quotes
# before doing the prefix check (same pattern as ensure_logged_in).
SWAP_URL="${RIPIO_APP_HOST}/swap"
log "Stage 3: verifying URL is ${SWAP_URL}"
CURR_URL=$(openclaw browser evaluate --fn '() => window.location.href')
CURR_URL="${CURR_URL%\"}"
CURR_URL="${CURR_URL#\"}"
if ! echo "$CURR_URL" | grep -q "^${SWAP_URL}"; then
  log "ERROR: expected ${SWAP_URL} but current URL is: $CURR_URL"
  exit 1
fi
log "Swap page confirmed: $CURR_URL"

# --- Stage 4: close swap-welcome modal if present ---
# Detect and click via DOM, not via snapshot grep. `openclaw browser snapshot`
# returns an accessibility tree that does NOT include CSS class names or
# data-testid attributes, so a regex over the snapshot for "modalClose" or
# "swap_welcome_close_button" can never match. Find by id (which the close
# button uses) and verify the data-testid as a sanity check.
log "Stage 4: checking for swap-welcome modal"
sleep 2
CLOSE_RESULT=$(openclaw browser evaluate --fn '() => {
  const btn = document.getElementById("swap_welcome_close_button");
  if (!btn) return "not_present";
  if (btn.getAttribute("data-testid") !== "swap_welcome_close_button") return "wrong_testid";
  btn.click();
  return "closed";
}')
log "Stage 4 result: $CLOSE_RESULT"
case "$CLOSE_RESULT" in
  '"closed"'|'closed') log "Swap-welcome modal closed"; sleep 1 ;;
  '"not_present"'|'not_present') log "No swap-welcome modal (already closed or never appeared)" ;;
  *) log "ERROR: unexpected modal-close result: $CLOSE_RESULT"; exit 1 ;;
esac

# --- Stage 5: confirm the swap form card is present ---
# The buy form is identified by data-testid="swap_form_card".
log "Stage 5: confirming swap form is present"
FORM_RESULT=$(openclaw browser evaluate --fn '() => {
  const form = document.querySelector("[data-testid=\"swap_form_card\"]");
  return form ? "found" : "not_found";
}')
log "Swap form check: $FORM_RESULT"
if [ "$FORM_RESULT" != '"found"' ] && [ "$FORM_RESULT" != "found" ]; then
  log "ERROR: swap form (data-testid=swap_form_card) not found on page."
  exit 1
fi

# --- Stage 6: verify form, click Use max, click Preview swap, then click Confirm ---
# 1. Verify all four form fields exist with matching id+data-testid+text, and
#    that Preview swap is initially disabled.
# 2. Click "Use max" to populate the amount.
# 3. Confirm Preview swap is now enabled (signal that the amount filled in).
# 4. Click Preview swap to advance to the preview screen.
# 5. Verify the same button now shows "Confirm" instead of "Preview swap".
# 6. Click Confirm to submit the swap.
# The max-button testid embeds the origin currency (lowercased).
log "Stage 6: verifying form fields (origin=$ASSET_ORIGIN_UPPER, max button, target=$ASSET_TARGET_UPPER, preview-disabled)"
FORM_FIELDS=$(openclaw browser evaluate --fn "() => {
  const checks = [
    { id: 'swap_form_input_origin_dropdown-button_toggle', text: '$ASSET_ORIGIN_UPPER' },
    { id: 'swap_form_input_origin_${ASSET_ORIGIN_LOWER}_use_all_my_balance', text: 'Use max' },
    { id: 'swap_form_input_target_dropdown-button_toggle', text: '$ASSET_TARGET_UPPER' },
    { id: 'swap_form_confirm_button', text: 'Preview swap', disabled: true },
  ];
  for (const c of checks) {
    const el = document.querySelector('[data-testid=' + JSON.stringify(c.id) + ']');
    if (!el) return 'missing:' + c.id;
    if (el.id !== c.id) return 'wrong_id:' + c.id + ':' + el.id;
    const txt = (el.textContent || '').trim();
    if (!txt.includes(c.text)) return 'wrong_text:' + c.id + ':expected=' + c.text + ':got=' + txt;
    if (c.disabled === true && !el.hasAttribute('disabled')) return 'not_disabled:' + c.id;
    if (c.disabled === false && el.hasAttribute('disabled')) return 'unexpectedly_disabled:' + c.id;
  }
  return 'ok';
}")
log "Form fields check: $FORM_FIELDS"
case "$FORM_FIELDS" in
  '"ok"'|'ok') log "All form fields verified (Preview swap initially disabled)" ;;
  *) log "ERROR: form fields check failed: $FORM_FIELDS"; exit 1 ;;
esac

# Click "Use max" — this should populate the amount and enable Preview swap.
log "Stage 6: clicking Use max"
USE_MAX_RESULT=$(openclaw browser evaluate --fn "() => {
  const btn = document.getElementById('swap_form_input_origin_${ASSET_ORIGIN_LOWER}_use_all_my_balance');
  if (!btn) return 'not_found';
  if (btn.hasAttribute('disabled')) return 'disabled';
  btn.click();
  return 'clicked';
}")
log "Use max result: $USE_MAX_RESULT"
case "$USE_MAX_RESULT" in
  '"clicked"'|'clicked') log "Use max clicked" ;;
  *) log "ERROR: Use max click failed: $USE_MAX_RESULT"; exit 1 ;;
esac
sleep 1

# Confirm Preview swap is now enabled (signal that the amount filled in).
log "Stage 6: verifying Preview swap is now enabled"
PREVIEW_ENABLED=$(openclaw browser evaluate --fn '() => {
  const btn = document.getElementById("swap_form_confirm_button");
  if (!btn) return "not_found";
  if (btn.hasAttribute("disabled")) return "still_disabled";
  return "enabled";
}')
log "Preview swap state: $PREVIEW_ENABLED"
case "$PREVIEW_ENABLED" in
  '"enabled"'|'enabled') log "Preview swap is enabled" ;;
  *) log "ERROR: Preview swap not enabled after Use max: $PREVIEW_ENABLED"; exit 1 ;;
esac

# Click Preview swap. Validation already happened above — just click here.
log "Stage 6: clicking Preview swap"
PREVIEW_CLICK=$(openclaw browser evaluate --fn '() => {
  const btn = document.getElementById("swap_form_confirm_button");
  if (!btn) return "not_found";
  btn.click();
  return "clicked";
}')
log "Preview swap click result: $PREVIEW_CLICK"
case "$PREVIEW_CLICK" in
  '"clicked"'|'clicked') log "Preview swap clicked" ;;
  *) log "ERROR: Preview swap click failed: $PREVIEW_CLICK"; exit 1 ;;
esac
sleep 2

# Verify the button has flipped from "Preview swap" to "Confirm" — same
# element (same id and data-testid), different text content.
log "Stage 6: verifying Confirm button has replaced Preview swap"
CONFIRM_PRESENT=$(openclaw browser evaluate --fn '() => {
  const btn = document.getElementById("swap_form_confirm_button");
  if (!btn) return "not_found";
  if (btn.getAttribute("data-testid") !== "swap_form_confirm_button") return "wrong_testid";
  const txt = (btn.textContent || "").trim();
  if (/preview swap/i.test(txt)) return "still_preview:" + txt;
  if (!/confirm/i.test(txt)) return "wrong_text:" + txt;
  return "ok";
}')
log "Confirm button check: $CONFIRM_PRESENT"
case "$CONFIRM_PRESENT" in
  '"ok"'|'ok') log "Confirm button is now showing" ;;
  *) log "ERROR: Confirm button not present after Preview swap click: $CONFIRM_PRESENT"; exit 1 ;;
esac

# Click Confirm. Same element as Preview swap (id/data-testid unchanged).
log "Stage 6: clicking Confirm"
CONFIRM_CLICK=$(openclaw browser evaluate --fn '() => {
  const btn = document.getElementById("swap_form_confirm_button");
  if (!btn) return "not_found";
  if (btn.hasAttribute("disabled")) return "disabled";
  btn.click();
  return "clicked";
}')
log "Confirm click result: $CONFIRM_CLICK"
case "$CONFIRM_CLICK" in
  '"clicked"'|'clicked') log "Confirm clicked" ;;
  *) log "ERROR: Confirm click failed: $CONFIRM_CLICK"; exit 1 ;;
esac
sleep 3

# --- Stage 7: verify swap success and report summary to user ---
# All elements looked up by id and verified by data-testid — no class matching.
# Validated elements (each must contain its expected ticker):
#   - swap_confirmation_title              — text: "Done!"
#   - swap_confirmation_title_convert      — text: "You swapped <ORIGIN> to <TARGET>"
#   - swap_confirmation_summary_converted  — origin amount  (e.g. "You swapped 28100.53 ARS")
#   - swap_confirmation_summary_receive    — target amount  (e.g. "You receive 0.00024114 BTC")
#   - swap_confirmation_summary_price      — price ratio    (e.g. "Price 1 BTC = 116528739.84 ARS")
#   - swap_confirmation_summary_fee        — fee            (e.g. "Ripio fee 0.00 ARS")
# Output is a multi-line summary block joined by a literal "|" so it survives
# bash word-splitting; we re-split on "|" before printing.
log "Stage 7: verifying swap confirmation page"
RESULT=$(openclaw browser evaluate --fn "() => {
  const checkAttrs = (el, id) => {
    if (!el) return 'not_found:' + id;
    if (el.getAttribute('data-testid') !== id) return 'wrong_testid:' + id;
    return null;
  };
  const text = (el) => (el.textContent || '').trim();

  // Title
  const title = document.getElementById('swap_confirmation_title');
  let err = checkAttrs(title, 'swap_confirmation_title');
  if (err) return 'ERROR:' + err;
  if (!/done!/i.test(text(title))) return 'ERROR:title_wrong_text:' + text(title);

  // Subtitle
  const subtitle = document.getElementById('swap_confirmation_title_convert');
  err = checkAttrs(subtitle, 'swap_confirmation_title_convert');
  if (err) return 'ERROR:' + err;
  const expectedSubtitle = 'You swapped $ASSET_ORIGIN_UPPER to $ASSET_TARGET_UPPER';
  if (!text(subtitle).includes(expectedSubtitle)) return 'ERROR:subtitle_wrong_text:expected=' + expectedSubtitle + ':got=' + text(subtitle);

  // Origin amount
  const converted = document.getElementById('swap_confirmation_summary_converted');
  err = checkAttrs(converted, 'swap_confirmation_summary_converted');
  if (err) return 'ERROR:' + err;
  if (!text(converted).includes('$ASSET_ORIGIN_UPPER')) return 'ERROR:converted_missing_origin:' + text(converted);

  // Target amount
  const receive = document.getElementById('swap_confirmation_summary_receive');
  err = checkAttrs(receive, 'swap_confirmation_summary_receive');
  if (err) return 'ERROR:' + err;
  if (!text(receive).includes('$ASSET_TARGET_UPPER')) return 'ERROR:receive_missing_target:' + text(receive);

  // Price (must mention both tickers)
  const price = document.getElementById('swap_confirmation_summary_price');
  err = checkAttrs(price, 'swap_confirmation_summary_price');
  if (err) return 'ERROR:' + err;
  if (!text(price).includes('$ASSET_ORIGIN_UPPER')) return 'ERROR:price_missing_origin:' + text(price);
  if (!text(price).includes('$ASSET_TARGET_UPPER')) return 'ERROR:price_missing_target:' + text(price);

  // Fee
  const fee = document.getElementById('swap_confirmation_summary_fee');
  err = checkAttrs(fee, 'swap_confirmation_summary_fee');
  if (err) return 'ERROR:' + err;

  return 'OK::' + [text(converted), text(receive), text(price), text(fee)].join('|');
}")
log "Stage 7 raw result: $RESULT"

case "$RESULT" in
  '"OK::'*)
    SUMMARY=${RESULT#'"OK::'}
    SUMMARY=${SUMMARY%'"'}
    ;;
  'OK::'*)
    SUMMARY=${RESULT#'OK::'}
    ;;
  *)
    log "ERROR: swap confirmation check failed: $RESULT"
    exit 1
    ;;
esac

log "Swap completed successfully."
echo ""
echo "=== Swap result ==="
echo "$SUMMARY" | tr '|' '\n'
exit 0
