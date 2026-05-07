# Self-Contained a-personal-assistant — Docker Setup

Deployment guide for the self-contained a-personal-assistant image. Everything
needed to run the `ripio-*` skills (system libs, Chromium, browser config,
skill files, gateway config) is baked into the image; bringing up a fresh
container takes two commands once the prerequisites are in place.

For the legacy "build OpenClaw separately, mount skills, configure browser by
hand" workflow, see `openclaw-instructions.md`.

## Prerequisites

1. **Docker Desktop** (or any Docker engine + Compose v2) running.
2. **Nothing else holding port 18789** — the gateway will fail to bind
   otherwise. On a fresh machine this is usually a non-issue. See "Port
   18789 already in use" below if you previously ran the upstream OpenClaw
   setup script on this machine.

That's it. The image is pulled from GHCR; no source builds, no
`openclaw:local` step, no Node toolchain on the host.

### Port 18789 already in use

Skip this section if you've never run the upstream OpenClaw setup script
(`~/src/personal/openclaw/scripts/docker/setup.sh`) on this machine.

That script leaves behind a host-side `openclaw-gateway` Node process
wrapped in a launchd agent (`ai.openclaw.gateway`) that auto-respawns on
every login — a one-shot `kill` won't stick. Clean it up:

```bash
# Tear down the upstream openclaw compose stack if present
docker compose -f ~/src/personal/openclaw/docker-compose.yml down --remove-orphans 2>/dev/null || true

# Disable and unload the launchd agent that auto-respawns the host gateway
PLIST=~/Library/LaunchAgents/ai.openclaw.gateway.plist
if [ -f "$PLIST" ]; then
  launchctl unload "$PLIST" 2>/dev/null || true
  launchctl disable "gui/$(id -u)/ai.openclaw.gateway" 2>/dev/null || true
  # Optional — delete the plist entirely so it can't be re-loaded:
  # rm "$PLIST"
fi

# Kill any remaining non-Docker process holding 18789
lsof -nP -iTCP:18789 -sTCP:LISTEN | awk 'NR>1 && $1 !~ /docker|com\.docke/ {print $2}' \
  | xargs -r kill
```

Verify nothing user-owned is left on 18789 — only `com.docker` (or empty
if Docker isn't running yet):

```bash
launchctl list | grep openclaw           # should print nothing
lsof -nP -iTCP:18789 -sTCP:LISTEN        # com.docker only, or empty
```

## First-Time Setup

The image is published at
`ghcr.io/cristianperez06/a-personal-assistant:latest` (multi-arch
amd64+arm64, public). On a clean machine:

```bash
git clone https://github.com/CristianPerez06/a-personal-assistant.git
cd a-personal-assistant

# 1. Create your env file from the template
cp .env.example .env

# 2. Generate a stable gateway token and write it to .env (replaces the
#    empty OPENCLAW_GATEWAY_TOKEN= line)
TOKEN=$(openssl rand -hex 32)
sed -i.bak "s|^OPENCLAW_GATEWAY_TOKEN=.*|OPENCLAW_GATEWAY_TOKEN=${TOKEN}|" .env && rm .env.bak

# 3. Open .env and fill in:
#      - LLM_API_KEY    (API key for whatever provider LLM_MODEL points at)
#      - LLM_MODEL      (e.g. openai/gpt-5, openrouter/anthropic/claude-sonnet-4-6)
#      - TELEGRAM_BOT_TOKEN  (from @BotFather)
#      - RIPIO_EMAIL, RIPIO_PASSWORD
#      - asset config (RIPIO_DCA_ASSET_ORIGIN / _TARGET)
$EDITOR .env

# 4. Pull the published image and start
docker compose pull
docker compose up -d
```

`docker compose up` will refuse to start if any of `OPENCLAW_GATEWAY_TOKEN`,
`LLM_API_KEY`, `LLM_MODEL`, or `TELEGRAM_BOT_TOKEN` are missing.

First pull downloads ~1.3 GB (Chromium + system libs included). Subsequent
`pull && up -d` cycles only fetch changed layers.

### Build from source instead

If you've made local changes to the Dockerfile, entrypoint, or skills and
want to test them before pushing, swap the last command for:

```bash
docker compose up -d --build
```

This builds from the `Dockerfile` in this checkout (using the pinned
upstream OpenClaw base image from GHCR) and tags the result with the
same GHCR coordinate as the published image — so the next plain
`docker compose up -d` keeps using your local build until the next
`pull` overwrites it.

The entrypoint will print the dashboard URL with your token embedded right
before the gateway starts. Check the startup logs:

```bash
docker compose logs a-personal-assistant | grep -A3 "Dashboard URL"
```

You'll see something like:

```
================================================================
  Dashboard URL (open this in your browser to authenticate):

    http://127.0.0.1:18789/?token=abc123...

================================================================
```

Open that URL in your browser. It stores the token in localStorage and
authenticates you for future visits to `http://localhost:18789/`.

> **First open in incognito/private window** if this machine previously ran
> a different deployment of the gateway. Old localStorage from a prior
> container will conflict with the new token and cause persistent
> "unauthorized: token mismatch" errors. Once authenticated successfully in
> incognito, you can clear localStorage in your normal browser
> (DevTools → Application → Storage → Clear site data) and use it from
> there onward.

### Verifying the Model Wiring

The entrypoint bakes everything model-related from `.env` on every start:

- **`$LLM_MODEL`** — slug of the form `<provider>/<model>` (e.g.
  `openai/gpt-5`). The provider name (everything before the first `/`)
  drives which OpenClaw plugin and auth profile get pinned.
- **`$LLM_API_KEY`** — written into
  `agents/main/agent/auth-profiles.json` under
  `<provider>:default` (chmod 600). The agent's auth file does not yet
  support SecretRef indirection, so the key lands as a literal in the
  named volume (private to this container).
- **`$TELEGRAM_BOT_TOKEN`** — stored as a **SecretRef** pointing at the
  env var, so the literal token never lands in `openclaw.json`.

Switching providers/models is a single edit to `.env` plus a recreate:

```bash
$EDITOR .env                                # change LLM_API_KEY and/or LLM_MODEL
docker compose up -d --force-recreate
```

After bring-up, verify end-to-end with a real inference call:

```bash
MODEL=$(grep '^LLM_MODEL=' .env | cut -d= -f2-)
docker exec -u node a-personal-assistant \
  node /app/dist/index.js infer model run --model "$MODEL" \
    --prompt "say hello in 3 words" 2>&1 | tail -10
```

A short reply means the provider, key, and model are all wired.

> **Don't use `openclaw configure`.** The entrypoint owns model selection
> via `.env`, so any choice the wizard writes will be overwritten on the
> next container start. Always change `LLM_MODEL` in `.env` instead.

## Telegram Pairing

When you first DM the bot, OpenClaw issues a pairing code. The Telegram
prompt looks like `openclaw pairing approve telegram XXXXXXXX`, but you
need to run that command inside the container — and you may also need to
restart for the approval to take effect on inbound messages.

1. List pending pairing requests (channel arg is required):

   ```bash
   docker exec a-personal-assistant openclaw pairing list telegram
   ```

2. Approve the code from the list:

   ```bash
   docker exec a-personal-assistant openclaw pairing approve telegram XXXXXXXX
   ```

3. Restart the container so the gateway picks up the updated allowlist:

   ```bash
   docker compose restart
   ```

If new messages keep generating fresh pairing codes after approval, the
allowlist file (`credentials/telegram-default-allowFrom.json`) was
written but the running gateway is still using its cached state — the
restart in step 3 is what makes the approval take effect.

## Why the Gateway Token

OpenClaw protects the dashboard with a token. Without setting one explicitly,
the gateway generates a random token on every fresh deployment, which means:

- You'd have to fish the token out of the container config every time.
- Your browser's localStorage from a previous deployment would mismatch the
  new container, blocking dashboard access until cleared.

Setting `OPENCLAW_GATEWAY_TOKEN` in `.env` pins it. The same token is used
on every container start, so the dashboard URL stays valid across rebuilds.
The compose file enforces that this var is set — `docker compose up` will
refuse to start without it.

The gateway reads this env var live on every request — it does **not**
persist to `openclaw.json`. So `cat /home/node/.openclaw/openclaw.json`
won't show a token field; that's expected and correct. The source of truth
for the token is your `.env` file.

## What the Image Contains

Built from `Dockerfile`, on top of the pinned upstream OpenClaw image
(`ghcr.io/openclaw/openclaw:2026.4.27`). Bump the `FROM` tag in the
Dockerfile when intentionally upgrading OpenClaw.

- Chromium system libs (`libnspr4`, `libnss3`, `libcairo2`, `libpango-1.0-0`, etc.)
- Playwright Chromium binary at `/home/node/.cache/ms-playwright/chromium-XXXX/chrome-linux/chrome`
- Skills at `/opt/a-personal-assistant/skills/` (a non-mount location)
- `docker-entrypoint.sh` runs as root on every start to:
  - `chown -R node:node /home/node/.openclaw` (defensive)
  - Copy `/opt/a-personal-assistant/skills/` → `/home/node/.openclaw/workspace/skills/`
  - Set `gateway.mode=local` and the five `browser.*` config values
  - Derive provider from `$LLM_MODEL` (everything before the first `/`)
  - Write `agents/main/agent/auth-profiles.json` with the API key from
    `$LLM_API_KEY` under `<provider>:default` (chmod 600)
  - Set `auth.profiles.<provider>:default`, `agents.defaults.model.primary`
    (= `$LLM_MODEL`), `agents.defaults.models`, and the
    `<provider>` + `telegram` plugin enables
  - Set `channels.telegram.botToken` as a SecretRef pointing at
    `$TELEGRAM_BOT_TOKEN`, plus `channels.telegram.enabled`
  - Print the dashboard URL with the token
  - `exec runuser -u node -- node dist/index.js gateway --bind lan --port 18789`

Every container start guarantees a known-good config and the latest baked-in
skills. You should never need to run `openclaw configure`,
`openclaw config set`, `docker cp skills/...`, or `docker exec ... chown`
manually.

## Common Tasks

### Drop into the container and use it as a normal shell

```bash
  docker exec -it a-personal-assistant bash
```

### Update to a newer published image

When new commits land on `main`, the GitHub Actions workflow rebuilds and
republishes `ghcr.io/cristianperez06/a-personal-assistant:latest`. To
update an existing deployment:

```bash
docker compose pull
docker compose up -d
```

Compose recreates the container if the pulled image has a new digest;
otherwise it's a no-op. Volumes (config, workspace, plugin runtime deps)
survive the recreate.

> **Pinning to a specific build:** for production deploys where you don't
> want surprise updates, change the `image:` line in `docker-compose.yml`
> from `:latest` to `:<commit-sha>`. The workflow tags every build with
> its commit SHA in addition to `latest`.

### Update skills (local-dev iteration)

Edit anything under `skills/`, then rebuild from source so the entrypoint
re-syncs the new files into the workspace volume:

```bash
docker compose up -d --build
```

For changes that have already landed on `main` and been published, just
use the "Update to a newer published image" recipe above instead.

### Rotate the LLM API key, switch providers, or rotate the Telegram bot token

All three live in `.env`. To rotate or switch, edit `.env` and recreate
so the entrypoint re-bakes everything:

```bash
$EDITOR .env                                  # change LLM_API_KEY, LLM_MODEL, or TELEGRAM_BOT_TOKEN
docker compose up -d --force-recreate
```

Verify the LLM is responding after the change:

```bash
MODEL=$(grep '^LLM_MODEL=' .env | cut -d= -f2-)
docker exec -u node a-personal-assistant \
  node /app/dist/index.js infer model run --model "$MODEL" \
    --prompt "say hello in 3 words" 2>&1 | tail -10
```

A short reply means the new key (and/or model) works.

### Change credentials or asset config

Edit `.env`, then recreate the container:

```bash
docker compose up -d
```

### Get the dashboard URL again

If you've lost it:

```bash
echo "http://127.0.0.1:18789/?token=$(grep '^OPENCLAW_GATEWAY_TOKEN=' .env | cut -d= -f2-)"
```

### View logs

```bash
docker compose logs -f               # all output, follow
docker compose logs --tail 100       # last 100 lines
```

### Get a shell in the container

```bash
docker exec -it a-personal-assistant bash
```

### Stop / restart

```bash
docker compose stop                  # keep state, just stop processes
docker compose restart               # quick cycle
docker compose down                  # stop + remove container (volumes survive)
docker compose up -d                 # bring it back
```

## Verifying the Browser Stack

After the gateway is up, run:

```bash
docker exec a-personal-assistant node /app/dist/index.js browser navigate https://example.com
```

If this returns without error, every layer is wired up.

## Volumes

Three named volumes persist data across container recreations:

| Volume                                              | Purpose                                     |
| --------------------------------------------------- | ------------------------------------------- |
| `a-personal-assistant_openclaw-config`              | OpenClaw config (`openclaw.json`), pairing  |
| `a-personal-assistant_openclaw-workspace`           | Workspace, including the auto-synced skills |
| `a-personal-assistant_openclaw-plugin-runtime-deps` | Plugin runtime cache                        |

To start truly from scratch (re-pair, etc.):

```bash
docker compose down
docker volume rm a-personal-assistant_openclaw-config a-personal-assistant_openclaw-workspace a-personal-assistant_openclaw-plugin-runtime-deps
docker compose up -d --build
```

## Troubleshooting

### Gateway won't start, says `existing config is missing gateway.mode`

The entrypoint sets this on every start, so this shouldn't happen. If it
does, the entrypoint didn't run — check `docker compose logs` for entrypoint
output (`[a-personal-assistant-entrypoint]` lines). If the entrypoint failed before the
config-pin step, fix that error.

### Dashboard says `unauthorized: token mismatch`

Most reliable fix — open the dashboard URL in a fresh **incognito/private
window**. That guarantees empty localStorage, so the token from the URL
gets used as-is.

Alternative: clear localStorage for `http://localhost:18789/` in your normal
browser (DevTools → Application → Storage → Clear site data) and reopen
the URL.

If that's not enough, the gateway-side token might have drifted from your
`.env` (rare — only happens if an older container persisted a token to the
config file before we switched to the env-var approach). Wipe the config
volume to force re-bootstrap from `.env`:

```bash
docker compose down
docker volume rm a-personal-assistant_openclaw-config
docker compose up -d
```

### Dashboard says `token mismatch` even with a fresh incognito window AND the URL token matches `.env`

Something other than the Docker container is answering on port 18789 —
typically a host-side `openclaw-gateway` node process left over from a
previous run. Two listeners can race for connections on macOS, and the
host one wins some of them with its own (different) token.

Confirm by checking the gateway log — if there are _no_ recent
"unauthorized" entries despite the browser error, the request never
reached Docker:

```bash
docker exec a-personal-assistant sh -c 'tail -200 /tmp/openclaw/openclaw-*.log' \
  | grep -iE 'unauth|token_mismatch'
```

Find and kill the imposter:

```bash
lsof -nP -iTCP:18789 -sTCP:LISTEN
# Kill any PID that is NOT a com.docker process
```

Then reload the dashboard URL.

### Dashboard says `unauthorized: too many failed authentication attempts`

A rate limiter triggered after repeated token-mismatch attempts. Restart
the gateway to clear it:

```bash
docker compose restart a-personal-assistant
```

Then open the dashboard URL in a fresh incognito window (see above) so you
don't immediately re-trigger the limiter with a stale browser-side token.

### `EACCES: permission denied` reading `/home/node/.openclaw/...`

`docker exec` defaults to user `root`. Any openclaw CLI command run that
way (`configure`, `config patch`, `models auth login`, etc.) will rewrite
files in `/home/node/.openclaw` as root, after which the gateway — which
runs as `node` — can no longer read them.

Fix in place:

```bash
docker exec a-personal-assistant chown -R node:node /home/node/.openclaw
```

To avoid the issue, **always pass `-u node` when running openclaw CLI
commands inside the container**:

```bash
docker exec -u node -it a-personal-assistant node /app/dist/index.js <command>
```

### `mkdir: ... Operation not supported` during build

Docker Desktop / VirtioFS quirk. The Dockerfile doesn't do any mkdir steps
in problematic places, so this shouldn't occur. If you hit it on a
Dockerfile change, move the file operation into the entrypoint instead.

### Logs say `HTTP 401` (e.g. "User not found", "Invalid API key")

The LLM API key in `auth-profiles.json` is no longer valid — most likely
revoked, regenerated, or the key in `.env` was truncated/wrong-provider.
Generate a fresh key from your provider, paste it into `.env`, and
recreate so the entrypoint re-bakes it:

```bash
$EDITOR .env                          # update LLM_API_KEY (and LLM_MODEL if you switched providers)
docker compose up -d --force-recreate
```

Verify the key in the volume now matches `.env`:

```bash
PROVIDER=$(grep '^LLM_MODEL=' .env | cut -d= -f2- | cut -d/ -f1)
docker exec -u node a-personal-assistant \
  node -e "console.log(JSON.parse(require('fs').readFileSync('/home/node/.openclaw/agents/main/agent/auth-profiles.json','utf8')).profiles['$PROVIDER:default'].key.slice(0,12))"
grep '^LLM_API_KEY=' .env | cut -d= -f2- | cut -c1-12
```

Both prefixes should match. Then re-run an `infer model run` test.

### Agent replies "the browser is not running" or tries to spawn a sub-agent

Symptoms: dashboard agent says it can't run a skill because the browser
isn't running, or it tries tools like `sessions_spawn` with hallucinated
agent IDs (e.g. `ripio-dca-agent`), or it never invokes the skill at all
and just chats back asking what you want.

Root cause is almost always **model capability**. The model in `LLM_MODEL`
can't reliably handle OpenClaw's skill-invocation pattern (read SKILL.md →
run scripts via shell). Switch to a stronger tool-using model — e.g.
`openai/gpt-5`, `openrouter/anthropic/claude-sonnet-4-6`, or
`openrouter/anthropic/claude-opus-4-7`:

```bash
$EDITOR .env                          # change LLM_MODEL (and LLM_API_KEY if the new model is on a different provider)
docker compose up -d --force-recreate
```

Models known to fail this consistently: `openrouter/auto` (random routing,
often hits weak models), small/quantized free models, models without first-
class tool-use training.

The "browser not running" reply specifically is also misleading because
OpenClaw doesn't run Chromium persistently — it launches on demand for
each browser action. Skill scripts include `openclaw browser start` at the
top to force a launch and stop the agent's planning step from bailing on a
literal `running:false` reading.

### Plugin crashes with `Cannot find package '<name>' imported from /var/lib/openclaw/plugin-runtime-deps/openclaw-<version>-<hash>/...`

The `openclaw-plugin-runtime-deps` named volume caches OpenClaw's plugin
runtime modules under a path that includes the OpenClaw build hash (e.g.
`openclaw-2026.4.27-f53b52ad6d21`). When the OpenClaw base image is bumped
to a new version, the hash changes — but the cached volume still has the
old layout, so the gateway tries to load modules from a path whose
contents don't match what the new build expects.

Symptom: on first start after the bump, plugins like `telegram` crash-loop
with errors like `Cannot find package 'json5' imported from /var/lib/openclaw/plugin-runtime-deps/openclaw-<new-version>-<hash>/...`.

Fix — drop the runtime deps volume so the gateway re-stages cleanly:

```bash
docker compose down
docker volume rm a-personal-assistant_openclaw-plugin-runtime-deps
docker compose up -d
```

The next start will re-install the bundled deps (~40 s, log line
`[plugins] staging bundled runtime deps before gateway startup`). The
config and workspace volumes are untouched.

### `Chrome CDP websocket ... not reachable`

The browser config is pointing at a stale Chromium path. The entrypoint
auto-detects the path on every start, so this means the bundled Chromium is
missing. Rebuild:

```bash
docker compose up -d --build
```

If the rebuild succeeds and the issue persists, check that the image actually
contains Chromium:

```bash
docker exec a-personal-assistant find /home/node/.cache/ms-playwright -name chrome -type f
```

## How the Published Image Gets Built

`.github/workflows/build.yml` rebuilds the image on every push to `main`
(plus manual `workflow_dispatch` runs) and pushes to GHCR with two tags:

- `:latest` — moving pointer for casual consumers
- `:<commit-sha>` — immutable reference, useful for pinning a deploy to
  a known build

The build is multi-arch (`linux/amd64` + `linux/arm64`) so the same image
runs on x86 servers, Apple Silicon, Raspberry Pi, and Oracle Cloud Free
Tier ARM. Auth uses the workflow's built-in `GITHUB_TOKEN` — no secrets
configured anywhere. The package's visibility is set to public on GHCR,
so consumers don't need `docker login ghcr.io`.
