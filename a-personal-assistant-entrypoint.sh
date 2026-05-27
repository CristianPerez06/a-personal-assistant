#!/usr/bin/env sh
# Entrypoint for the self-contained a-personal-assistant image.
#
# Runs as root so it can chown the workspace volume if Docker initialized it
# with bad ownership (this happens on Mac / VirtioFS when the named volume's
# mount point doesn't exist in the source image). After setup, drops
# privileges to `node` via `runuser` for both config commands and the
# gateway itself.
#
# On every container start:
#   1. Ensure /home/node/.openclaw ownership is node:node.
#   2. Sync bundled skills (/opt/a-personal-assistant/skills) into the workspace volume.
#   3. Pin gateway.mode + browser.* config (as node).
#   4. Bake credentials from env: OpenRouter API key into auth-profiles.json,
#      Telegram bot token into openclaw.json as a SecretRef pointing at env.
#   5. Disable heartbeats (request/response bot — no proactive runs needed).
#   6. Print the dashboard URL with the token included.
#   7. exec the original CMD (gateway) as node.
set -e

log() { echo "[a-personal-assistant-entrypoint] $*"; }

# 1. Defensive ownership fix for the workspace volume.
log "Ensuring /home/node/.openclaw is owned by node:node"
chown -R node:node /home/node/.openclaw

# 2. Sync bundled skills into the workspace volume.
log "Syncing skills into /home/node/.openclaw/workspace/skills"
mkdir -p /home/node/.openclaw/workspace/skills
cp -rT /opt/a-personal-assistant/skills /home/node/.openclaw/workspace/skills
chown -R node:node /home/node/.openclaw/workspace/skills

# 3. Pin config (gateway.mode + browser.*).
CHROME=$(find /home/node/.cache/ms-playwright -name chrome -type f | head -1)
if [ -z "$CHROME" ]; then
  echo "[a-personal-assistant-entrypoint] FATAL: bundled Chromium not found in image; rebuild required" >&2
  exit 1
fi
log "Pinning gateway and browser config (chromium=$CHROME)"
runuser -u node -- node /app/dist/index.js config set gateway.mode local >/dev/null
runuser -u node -- node /app/dist/index.js config set browser.executablePath "$CHROME" >/dev/null
runuser -u node -- node /app/dist/index.js config set browser.headless true >/dev/null
runuser -u node -- node /app/dist/index.js config set browser.noSandbox true >/dev/null
runuser -u node -- node /app/dist/index.js config set browser.enabled true >/dev/null
runuser -u node -- node /app/dist/index.js config set browser.extraArgs '["--disable-features=dbus","--disable-gpu"]' --strict-json >/dev/null

# 4. Bake credentials and model selection from env into the config volume.
#
# LLM_MODEL is a slug like "openai/gpt-5", "openrouter/anthropic/claude-sonnet-4-6",
# or "nvidia/minimaxai/minimax-m2.7". The provider is everything before the first
# slash; we use it to write the auth profile under "<provider>:default" and to
# enable the matching plugin.
LLM_PROVIDER="${LLM_MODEL%%/*}"
if [ -z "$LLM_PROVIDER" ] || [ "$LLM_PROVIDER" = "$LLM_MODEL" ]; then
  echo "[a-personal-assistant-entrypoint] FATAL: LLM_MODEL must be of the form '<provider>/<model>' (got: '$LLM_MODEL')" >&2
  exit 1
fi

# API key: written literally into agents/main/agent/auth-profiles.json (that
# file is read by the agent and there's no SecretRef indirection for it).
# The volume is private to this container and the file is chmod 600.
log "Writing $LLM_PROVIDER API key to auth-profiles.json"
mkdir -p /home/node/.openclaw/agents/main/agent
cat > /home/node/.openclaw/agents/main/agent/auth-profiles.json <<EOF
{
  "version": 1,
  "profiles": {
    "${LLM_PROVIDER}:default": {
      "type": "api_key",
      "provider": "${LLM_PROVIDER}",
      "key": "${LLM_API_KEY}"
    }
  }
}
EOF
chown -R node:node /home/node/.openclaw/agents
chmod 600 /home/node/.openclaw/agents/main/agent/auth-profiles.json

log "Pinning auth profile, model, and plugin enables (provider=$LLM_PROVIDER, model=$LLM_MODEL)"
runuser -u node -- node /app/dist/index.js config set "auth.profiles.${LLM_PROVIDER}:default" "{\"provider\":\"${LLM_PROVIDER}\",\"mode\":\"api_key\"}" --strict-json >/dev/null
runuser -u node -- node /app/dist/index.js config set agents.defaults.model.primary "$LLM_MODEL" >/dev/null
runuser -u node -- node /app/dist/index.js config set agents.defaults.models "{\"$LLM_MODEL\":{}}" --strict-json --replace >/dev/null
runuser -u node -- node /app/dist/index.js config set "plugins.entries.${LLM_PROVIDER}.enabled" true >/dev/null

log "Disabling heartbeat (this assistant is request/response only — no proactive runs)"
# Heartbeats fire scheduled LLM calls with the full tool catalog attached
# (~30k tokens/call on gpt-5). For a Telegram-driven request/response bot
# they burn credits for no benefit — the bot already wakes on every user
# message. Re-enable per-agent in agents.list[].heartbeat if you ever need
# proactive behavior.
runuser -u node -- node /app/dist/index.js config set agents.defaults.heartbeat.every "0m" >/dev/null

log "Pinning Telegram bot token and plugin enable"
# Telegram bot token: stored as a SecretRef so the literal token never lands
# in openclaw.json. The gateway resolves it from $TELEGRAM_BOT_TOKEN at runtime.
runuser -u node -- node /app/dist/index.js config set channels.telegram.botToken --ref-source env --ref-id TELEGRAM_BOT_TOKEN --ref-provider default >/dev/null
runuser -u node -- node /app/dist/index.js config set channels.telegram.enabled true >/dev/null
runuser -u node -- node /app/dist/index.js config set plugins.entries.telegram.enabled true >/dev/null

# 5. Print the dashboard URL with the token. The gateway reads
#    OPENCLAW_GATEWAY_TOKEN from env at startup and uses it as the auth
#    token. We require it to be set (docker-compose enforces this), so
#    we can construct the URL without waiting for the gateway to start.
echo ""
echo "================================================================"
echo "  Dashboard URL (open this in your browser to authenticate):"
echo ""
echo "    http://127.0.0.1:18789/?token=${OPENCLAW_GATEWAY_TOKEN}"
echo ""
echo "================================================================"
echo ""

# 6. Hand off to CMD as node.
log "Ready. Starting gateway as node..."
exec runuser -u node -- "$@"
