#!/usr/bin/env bash
# One-shot installer for a-personal-assistant on macOS.
# Idempotent: re-run anytime; completed steps are skipped.
set -euo pipefail

if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'
  RESET=$'\033[0m'
else
  BOLD=; DIM=; RED=; GREEN=; YELLOW=; BLUE=; RESET=
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

TOTAL_PHASES=7
CURRENT_PHASE=""
CURRENT_PHASE_NUM=0

phase() {
  CURRENT_PHASE_NUM=$((CURRENT_PHASE_NUM + 1))
  CURRENT_PHASE="$1"
  echo
  echo "${BOLD}${BLUE}[${CURRENT_PHASE_NUM}/${TOTAL_PHASES}] ${CURRENT_PHASE}${RESET}"
}

ok()    { echo "  ${GREEN}✓${RESET} $1"; }
skip()  { echo "  ${DIM}✓ already configured: $1${RESET}"; }
info()  { echo "  ${BLUE}→${RESET} $1"; }
warn()  { echo "  ${YELLOW}!${RESET} $1"; }
fail()  { echo "  ${RED}✗${RESET} $1"; }

on_error() {
  local exit_code=$?
  echo
  fail "${BOLD}Step ${CURRENT_PHASE_NUM} failed: ${CURRENT_PHASE}${RESET}"
  fail "Re-run ${BOLD}./bootstrap.sh${RESET} to resume — completed steps are skipped."
  exit "$exit_code"
}
trap on_error ERR

confirm() {
  local prompt="${1:-Continue?} [Y/n] "
  local reply
  read -r -p "$prompt" reply </dev/tty
  reply="${reply:-Y}"
  [[ "$reply" =~ ^[Yy] ]]
}

# ----------------------------------------------------------------------------
# Phase 1 — Preflight
# ----------------------------------------------------------------------------
phase "Preflight"

if [[ "$(uname -s)" != "Darwin" ]]; then
  fail "bootstrap.sh currently supports macOS only. Detected: $(uname -s)."
  exit 1
fi
ok "macOS detected ($(uname -m))"

if ! xcode-select -p >/dev/null 2>&1; then
  info "Installing Xcode Command Line Tools (a system dialog will appear; click Install)…"
  xcode-select --install >/dev/null 2>&1 || true
  until xcode-select -p >/dev/null 2>&1; do
    sleep 5
    echo "  ${DIM}…waiting for Xcode CLT install to finish${RESET}"
  done
  ok "Xcode Command Line Tools installed"
else
  skip "Xcode Command Line Tools"
fi

cat <<EOF

${BOLD}This script will:${RESET}
  • Install Homebrew (if missing)
  • Install Node 20+ via Homebrew (if missing)
  • Install Docker Desktop via Homebrew (if missing) and start it
  • Pre-download Chromium for Playwright (used by the skill-authoring workflow)
  • Walk you through filling in .env (LLM API key, optional Telegram, optional Ripio)
  • Pull the a-personal-assistant Docker image and start the container

It's safe to re-run: completed steps are skipped automatically.

EOF

if ! confirm "Continue?"; then
  echo "Aborted."
  exit 0
fi

# ----------------------------------------------------------------------------
# Phase 2 — Homebrew
# ----------------------------------------------------------------------------
phase "Homebrew"

if command -v brew >/dev/null 2>&1; then
  skip "Homebrew at $(brew --prefix)"
else
  info "Installing Homebrew (this may take a few minutes)…"
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
  ok "Homebrew installed at $(brew --prefix)"
fi

# ----------------------------------------------------------------------------
# Phase 3 — Node ≥ 20
# ----------------------------------------------------------------------------
phase "Node ≥ 20"

node_ok=false
if command -v node >/dev/null 2>&1; then
  node_major="$(node -v | sed -E 's/^v([0-9]+).*/\1/')"
  if [[ "$node_major" -ge 20 ]]; then
    node_ok=true
  fi
fi

if $node_ok; then
  skip "Node $(node -v)"
else
  info "Installing Node via Homebrew…"
  brew install node
  ok "Node $(node -v) installed"
fi

# ----------------------------------------------------------------------------
# Phase 4 — Docker Desktop
# ----------------------------------------------------------------------------
phase "Docker Desktop"

wait_for_docker() {
  local deadline=$(( $(date +%s) + 180 ))
  while ! docker info >/dev/null 2>&1; do
    if (( $(date +%s) > deadline )); then
      fail "Docker daemon didn't become ready within 3 minutes."
      fail "Open Docker Desktop manually, accept any prompts, then re-run ./bootstrap.sh."
      return 1
    fi
    sleep 3
    echo "  ${DIM}…waiting for Docker to start${RESET}"
  done
}

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  skip "Docker running ($(docker --version | sed -E 's/Docker version //'))"
elif command -v docker >/dev/null 2>&1; then
  info "Docker is installed but not running. Launching Docker Desktop…"
  open -a Docker
  warn "If Docker shows a license or privileged-helper prompt, accept it. I'll wait."
  wait_for_docker
  ok "Docker daemon ready"
else
  info "Installing Docker Desktop via Homebrew cask (this downloads ~600MB)…"
  brew install --cask docker
  info "Launching Docker Desktop for the first time…"
  open -a Docker
  warn "Docker Desktop just opened. ${BOLD}Accept the license and any privileged-helper prompts in the GUI${RESET}, then come back here. I'll wait."
  wait_for_docker
  ok "Docker daemon ready"
fi

# ----------------------------------------------------------------------------
# Phase 5 — Playwright Chromium (for skill authoring)
# ----------------------------------------------------------------------------
phase "Playwright Chromium (for skill authoring)"

PLAYWRIGHT_CACHE="$HOME/Library/Caches/ms-playwright"
if [[ -d "$PLAYWRIGHT_CACHE" ]] && \
   find "$PLAYWRIGHT_CACHE" -maxdepth 1 -type d -name 'chromium-*' | grep -q .; then
  skip "Playwright Chromium cached at $PLAYWRIGHT_CACHE"
else
  info "Downloading Chromium for Playwright codegen (one-time, ~150MB)…"
  if npx --yes playwright@latest install chromium; then
    ok "Playwright Chromium installed"
  else
    warn "Playwright install failed. Skill authoring via 'npx playwright codegen' may need this run manually later. Continuing."
  fi
fi

# ----------------------------------------------------------------------------
# Phase 6 — .env configuration
# ----------------------------------------------------------------------------
phase ".env configuration"

ENV_FILE="$REPO_DIR/.env"
declare -A CURRENT=()

if [[ -f "$ENV_FILE" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue
    if [[ "$line" =~ ^([A-Z_][A-Z0-9_]*)=(.*)$ ]]; then
      CURRENT[${BASH_REMATCH[1]}]="${BASH_REMATCH[2]}"
    fi
  done < "$ENV_FILE"
fi

# Treat the .env.example placeholders as "unset".
is_real_value() {
  local val="$1"
  case "$val" in
    ""|"your-email-here"|"your-password-here"|"your-origin-asset"|"your-target-asset") return 1 ;;
    *) return 0 ;;
  esac
}

is_set() {
  is_real_value "${CURRENT[$1]:-}"
}

# OPENCLAW_GATEWAY_TOKEN — auto-generated, no prompt.
if is_set OPENCLAW_GATEWAY_TOKEN; then
  skip "OPENCLAW_GATEWAY_TOKEN already set"
else
  CURRENT[OPENCLAW_GATEWAY_TOKEN]="$(openssl rand -hex 32)"
  ok "OPENCLAW_GATEWAY_TOKEN generated"
fi

# LLM provider + key.
if is_set LLM_API_KEY && is_set LLM_MODEL; then
  skip "LLM provider already configured (${CURRENT[LLM_MODEL]})"
else
  echo
  echo "  ${BOLD}Pick an LLM provider:${RESET}"
  echo "    1) OpenAI       (https://platform.openai.com/api-keys)"
  echo "    2) OpenRouter   (https://openrouter.ai/keys)"
  echo "    3) NVIDIA       (https://build.nvidia.com/)"
  echo "    4) Custom       (paste a provider/model slug yourself)"
  llm_choice=""
  while [[ ! "$llm_choice" =~ ^[1-4]$ ]]; do
    read -r -p "  Choice [1-4]: " llm_choice </dev/tty
  done

  case "$llm_choice" in
    1) default_model="openai/gpt-5"; provider_label="OpenAI" ;;
    2) default_model="openrouter/anthropic/claude-sonnet-4-6"; provider_label="OpenRouter" ;;
    3) default_model="nvidia/minimaxai/minimax-m2.7"; provider_label="NVIDIA" ;;
    4) default_model=""; provider_label="custom provider" ;;
  esac

  if [[ "$llm_choice" == "4" ]]; then
    read -r -p "  Model slug (e.g. provider/model-name): " model_input </dev/tty
    CURRENT[LLM_MODEL]="$model_input"
  else
    read -r -p "  Model [${default_model}]: " model_input </dev/tty
    CURRENT[LLM_MODEL]="${model_input:-$default_model}"
  fi

  read -r -s -p "  ${provider_label} API key (hidden): " api_key </dev/tty
  echo
  CURRENT[LLM_API_KEY]="$api_key"
  ok "LLM configured: ${CURRENT[LLM_MODEL]}"
fi

# TELEGRAM_BOT_TOKEN — optional, blank is fine.
if [[ -n "${CURRENT[TELEGRAM_BOT_TOKEN]:-}" ]]; then
  skip "TELEGRAM_BOT_TOKEN already set"
else
  echo
  echo "  ${BOLD}Telegram bot (optional)${RESET}"
  echo "  Get a token from https://t.me/BotFather, or press Enter to skip."
  echo "  ${DIM}Without a token the dashboard still works; only the Telegram pathway is disabled.${RESET}"
  read -r -p "  TELEGRAM_BOT_TOKEN [skip]: " tg_token </dev/tty
  CURRENT[TELEGRAM_BOT_TOKEN]="${tg_token:-}"
  if [[ -n "$tg_token" ]]; then
    ok "Telegram token saved"
  else
    info "Telegram skipped"
  fi
fi

# Ripio — optional, prompted as a group.
if is_set RIPIO_EMAIL; then
  skip "Ripio credentials already configured"
else
  echo
  echo "  ${BOLD}Ripio credentials (optional)${RESET}"
  echo "  Needed by the ripio-login / ripio-buy / ripio-dca skills."
  if confirm "  Configure Ripio now?"; then
    read -r -p "  RIPIO_EMAIL: " ripio_email </dev/tty
    read -r -s -p "  RIPIO_PASSWORD (hidden): " ripio_password </dev/tty
    echo
    read -r -p "  RIPIO_DCA_ASSET_ORIGIN [ARS]: " ripio_origin </dev/tty
    read -r -p "  RIPIO_DCA_ASSET_TARGET [BTC]: " ripio_target </dev/tty
    CURRENT[RIPIO_EMAIL]="$ripio_email"
    CURRENT[RIPIO_PASSWORD]="$ripio_password"
    CURRENT[RIPIO_DCA_ASSET_ORIGIN]="${ripio_origin:-ARS}"
    CURRENT[RIPIO_DCA_ASSET_TARGET]="${ripio_target:-BTC}"
    ok "Ripio configured"
  else
    info "Ripio skipped"
  fi
fi

# Atomic write.
tmp="$ENV_FILE.tmp.$$"
cat > "$tmp" <<EOF
# Generated by bootstrap.sh — safe to edit by hand.
# Re-run ./bootstrap.sh to fill in any blanks without losing the values already set.

OPENCLAW_GATEWAY_TOKEN=${CURRENT[OPENCLAW_GATEWAY_TOKEN]}

LLM_API_KEY=${CURRENT[LLM_API_KEY]}
LLM_MODEL=${CURRENT[LLM_MODEL]}

TELEGRAM_BOT_TOKEN=${CURRENT[TELEGRAM_BOT_TOKEN]:-}

RIPIO_EMAIL=${CURRENT[RIPIO_EMAIL]:-}
RIPIO_PASSWORD=${CURRENT[RIPIO_PASSWORD]:-}
RIPIO_DCA_ASSET_ORIGIN=${CURRENT[RIPIO_DCA_ASSET_ORIGIN]:-}
RIPIO_DCA_ASSET_TARGET=${CURRENT[RIPIO_DCA_ASSET_TARGET]:-}
EOF
mv "$tmp" "$ENV_FILE"
chmod 600 "$ENV_FILE"
ok ".env written"

# ----------------------------------------------------------------------------
# Phase 7 — Boot
# ----------------------------------------------------------------------------
phase "Starting the container"

info "Pulling the latest image…"
docker compose pull
info "Starting the container…"
docker compose up -d

info "Waiting for the dashboard at http://127.0.0.1:18789/ to respond…"
deadline=$(( $(date +%s) + 60 ))
until curl -fsS -o /dev/null --max-time 2 "http://127.0.0.1:18789/" 2>/dev/null; do
  if (( $(date +%s) > deadline )); then
    warn "Dashboard didn't respond within 60s. Run 'docker compose logs' if it doesn't show up shortly."
    break
  fi
  sleep 2
done

echo
echo "${BOLD}${GREEN}Done.${RESET}"
echo
echo "  Dashboard:     ${BOLD}http://127.0.0.1:18789/${RESET}"
echo "  Pairing token: see OPENCLAW_GATEWAY_TOKEN in your .env file"
echo
echo "  Stop:    ${DIM}docker compose down${RESET}"
echo "  Logs:    ${DIM}docker compose logs -f${RESET}"
echo "  Update:  ${DIM}docker compose pull && docker compose up -d${RESET}"
echo

if command -v open >/dev/null 2>&1; then
  open "http://127.0.0.1:18789/" >/dev/null 2>&1 || true
fi
