#!/usr/bin/env bash
# TEMPLATE — copy this to skills/<your-skill-name>/scripts/<your-skill-name>.sh
# and edit. The helpers below are the conventions every skill in this repo uses.
#
# Usage:
#   <your-skill>.sh [args...]
#
# Exit codes (extend as needed; keep the meaning stable):
#   0 — success
#   1 — generic / unexpected error (selector not found, page didn't load, etc.)
#   2 — auth/data error (bad credentials, missing balance, etc.)
#   3 — branch needed: e.g. 2FA screen appeared (run again with --2fa <code>)
#   4 — branch needed: e.g. magic-link screen appeared (run again with --magic-link <token>)
#   5 — unknown post-action state (no known signal matched)

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

# Poll the page URL until it stabilizes (no change between consecutive checks).
# Returns the final URL on stdout. Use this after actions that trigger navigation
# instead of `sleep N` — it survives slow redirects without padding fast ones.
wait_for_url_stable() {
  local prev=""
  local curr=""
  for i in 1 2 3 4 5 6; do
    sleep 3
    curr=$(openclaw browser evaluate --fn '() => window.location.href' 2>/dev/null)
    if [ "$curr" = "$prev" ]; then
      echo "$curr"
      return 0
    fi
    prev="$curr"
  done
  echo "$curr"
}

# -----------------------------------------------------------------------------
# TODO: replace everything below with your skill's logic.
#
# Conventions:
#   - Read credentials and config from env vars passed in by the caller; never
#     hardcode anything from your Playwright codegen recording.
#   - Prefer `fill_by_id` / `click_by_id` over emitting raw `openclaw browser
#     evaluate` calls.
#   - When timing matters (e.g. TOTP), bundle multiple steps into one
#     `openclaw browser evaluate` call to minimize round-trips.
#   - On unexpected state, exit with a documented non-zero code and write the
#     reason to stderr. Do NOT retry or "creatively" recover — the agent layer
#     handles that based on your exit code.
# -----------------------------------------------------------------------------

echo "TODO: implement skill logic"
exit 1
