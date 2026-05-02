# OpenClaw Local Setup

## Prerequisites

1. Install and run Docker Desktop: [https://docs.docker.com/desktop/](https://docs.docker.com/desktop/)
2. Clone the OpenClaw repository: [https://github.com/openclaw/openclaw.git](https://github.com/openclaw/openclaw.git)

## Setup

1. Run the Docker setup script:

```bash
./scripts/docker/setup.sh
```

2. Choose the **Quickstart** settings during setup.

3. If you see this error:

```text
Gateway failed to start: Error: non-loopback Control UI requires gateway.controlUi.allowedOrigins (set explicit origins), or set gateway.controlUi.dangerouslyAllowHostHeaderOriginFallback=true to use Host-header origin fallback mode
```

Stop the container and run:

```bash
docker compose -f docker-compose.yml run --rm openclaw-cli config set gateway.controlUi.allowedOrigins '["http://127.0.0.1:18789"]' --strict-json
```

## Running the Container

Start (or restart) the container:

```bash
docker compose -f ~/src/personal/openclaw/docker-compose.yml up -d
```

To start only the gateway (without the CLI service):

```bash
docker compose -f ~/src/personal/openclaw/docker-compose.yml up -d openclaw-gateway
```

Stop the container:

```bash
docker compose -f ~/src/personal/openclaw/docker-compose.yml down
```

## Access the Dashboard

1. Open [http://localhost:18789/](http://localhost:18789/).
2. If prompted to authenticate, generate a new dashboard URL with token:

```bash
docker compose run --rm openclaw-cli dashboard --no-open
```

3. Open the generated URL.

## Pairing Troubleshooting

If you get this error:

```text
disconnected (1008): pairing required
```

1. List pairing requests:

```bash
docker compose exec openclaw-gateway node dist/index.js devices list
```

2. Approve the pending device using its ID:

```bash
docker compose exec openclaw-gateway node dist/index.js devices approve THE_DOCKER_CONTAINER_ID_HERE
```

## Browser Setup

1. Install system dependencies for Chromium:

```bash
docker compose -f ~/src/personal/openclaw/docker-compose.yml exec -u root openclaw-gateway \
  bash -c "apt-get update && apt-get install -y \
    libnspr4 libnss3 libatk1.0-0 libatk-bridge2.0-0 \
    libdbus-1-3 libcups2 libxkbcommon0 libatspi2.0-0 \
    libxcomposite1 libxdamage1 libxfixes3 libxrandr2 \
    libgbm1 libasound2 libcairo2 libpango-1.0-0 dbus && \
    mkdir -p /run/dbus && dbus-daemon --system --fork"
```

Verify: should see "Setting up libnspr4..." etc. in the output, or "already the newest version" if already installed.

2. Install Chromium via Playwright:

```bash
docker compose -f ~/src/personal/openclaw/docker-compose.yml exec openclaw-gateway \
  node /app/node_modules/playwright-core/cli.js install chromium
```

Verify: should see a download progress bar and "Chromium ... downloaded to ...".

3. Find the installed Chromium binary path:

```bash
docker compose -f ~/src/personal/openclaw/docker-compose.yml exec openclaw-gateway \
  find /home/node/.cache/ms-playwright -name chrome -type f
```

Verify: should print a path like `/home/node/.cache/ms-playwright/chromium-XXXX/chrome-linux/chrome`. If empty, step 2 failed.

4. Configure all browser settings in one batch. The Chromium path is auto-detected so it always matches whatever Playwright installed in step 2 (no hardcoded version):

```bash
docker compose -f ~/src/personal/openclaw/docker-compose.yml exec openclaw-gateway bash -c '
  CHROME=$(find /home/node/.cache/ms-playwright -name chrome -type f | head -1)
  if [ -z "$CHROME" ]; then echo "ERROR: chrome not found — re-run step 2"; exit 1; fi
  echo "Using Chromium at: $CHROME"
  node dist/index.js config set browser.executablePath "$CHROME" &&
  node dist/index.js config set browser.headless true &&
  node dist/index.js config set browser.noSandbox true &&
  node dist/index.js config set browser.enabled true &&
  node dist/index.js config set browser.extraArgs '\''["--disable-features=dbus","--disable-gpu","--user-data-dir=/tmp/openclaw-chrome"]'\'' --strict-json
'
```

If you ever need to update **just** the path (e.g. after Playwright reinstalls Chromium at a different version), this is the standalone equivalent:

```bash
docker compose -f ~/src/personal/openclaw/docker-compose.yml exec openclaw-gateway bash -c '
  CHROME=$(find /home/node/.cache/ms-playwright -name chrome -type f | head -1)
  echo "Setting executablePath to: $CHROME"
  node dist/index.js config set browser.executablePath "$CHROME"
'
```

What this sets:

- `browser.executablePath` — Chromium binary path.
- `browser.headless` — `true` (no display server inside containers).
- `browser.noSandbox` — `true` (Chrome's sandbox doesn't work inside containers).
- `browser.enabled` — `true` (turn the feature on).
- `browser.extraArgs` — disables D-Bus and GPU to avoid container connection errors, and pins Chromium's user-data dir to `/tmp/openclaw-chrome`. `/tmp` is wiped on every container restart, so stale profile locks can't carry over between runs.

Verify all five at once:

```bash
docker compose -f ~/src/personal/openclaw/docker-compose.yml exec openclaw-gateway bash -c '
  node dist/index.js config get browser.executablePath
  node dist/index.js config get browser.headless
  node dist/index.js config get browser.noSandbox
  node dist/index.js config get browser.enabled
  node dist/index.js config get browser.extraArgs
'
```

5. Add a D-Bus environment variable to the gateway container.

Open `~/src/personal/openclaw/docker-compose.yml` (or your `docker-compose.override.yml`) and add this line under the `openclaw-gateway` service's `environment` section, alongside the existing entries:

```yaml
DBUS_SESSION_BUS_ADDRESS: /dev/null
```

This disables D-Bus for Chrome to avoid connection errors inside the container.

6. Apply both the config changes and the new env var by recreating the gateway:

```bash
docker compose -f ~/src/personal/openclaw/docker-compose.yml up -d openclaw-gateway
```

Verify:

```bash
docker compose -f ~/src/personal/openclaw/docker-compose.yml logs --tail 20 openclaw-gateway
```

Should show the gateway starting up without errors.

7. End-to-end verification — confirm the full browser stack works before deploying skills:

```bash
docker compose -f ~/src/personal/openclaw/docker-compose.yml exec openclaw-gateway \
  node dist/index.js browser navigate https://example.com
```

If this returns without error (it should print a snapshot/page result), every layer is wired up correctly: apt deps, Chromium binary, OpenClaw browser plugin, and CDP connection.

If it fails, the most common causes — in order of likelihood — are:

- **`browser.executablePath not found`** — Playwright reinstalled Chromium at a different version. Re-run the standalone path-setter command from step 4 and `restart` the gateway.
- **Missing shared libraries** — apt deps got wiped by a `--force-recreate`. Re-run step 1.
- **`Chrome CDP websocket... not reachable`** — usually means one of the above. Check `docker compose ... logs openclaw-gateway` for the actual error.

## Environment Variables

Add environment variables for the DCA bot

Add `RIPIO_EMAIL`, `RIPIO_PASSWORD`, `RIPIO_DCA_ASSET_ORIGIN`, and `RIPIO_DCA_ASSET_TARGET` to the openclaw `.env` file (located next to `docker-compose.yml` in the openclaw repo):

```bash
## Ripio (DCA bot)
RIPIO_EMAIL=your-email@example.com
RIPIO_PASSWORD=your-password
RIPIO_DCA_ASSET_ORIGIN=your-origin-asset
RIPIO_DCA_ASSET_TARGET=your-target-asset
```

Then wire them into both services in the openclaw `docker-compose.yml` (`~/src/personal/openclaw/docker-compose.yml`). Add these lines to the `environment` section of both `openclaw-gateway` and `openclaw-cli`:

```yaml
RIPIO_EMAIL: ${RIPIO_EMAIL:-}
RIPIO_PASSWORD: ${RIPIO_PASSWORD:-}
RIPIO_DCA_ASSET_ORIGIN: ${RIPIO_DCA_ASSET_ORIGIN:-}
RIPIO_DCA_ASSET_TARGET: ${RIPIO_DCA_ASSET_TARGET:-}
```

After editing `.env` and `docker-compose.yml`, restart the container:

```bash
docker compose -f ~/src/personal/openclaw/docker-compose.yml up -d
```

Verify they're set:

```bash
docker exec openclaw-gateway env | grep RIPIO
```

## Deploying Skills

Copy the skill folder contents (note the `/.` source and trailing `/` destination to avoid nesting):

```bash
docker cp ~/src/personal/a-dca-bot/skills/. openclaw-gateway:/home/node/.openclaw/workspace/skills/
```

To copy a single file instead:

```bash
docker cp ~/src/personal/a-dca-bot/skills/ripio-login/SKILL.md \
  openclaw-gateway:/home/node/.openclaw/workspace/skills/ripio-login/SKILL.md
```

## Editing Files in the Container

```bash
  # Copy out
  docker cp openclaw-gateway:/home/node/.openclaw/openclaw.json ./openclaw.json

  # Edit it locally, then copy back
  docker cp ./openclaw.json openclaw-gateway:/home/node/.openclaw/openclaw.json
```
