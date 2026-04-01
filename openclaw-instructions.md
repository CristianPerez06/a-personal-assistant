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
    libgbm1 libasound2 dbus && \
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

4. Configure OpenClaw to use it (use the path from step 3):

```bash
docker compose -f ~/src/personal/openclaw/docker-compose.yml exec openclaw-gateway \
  node dist/index.js config set browser.executablePath /home/node/.cache/ms-playwright/chromium-1217/chrome-linux/chrome
```

Verify:

```bash
docker compose -f ~/src/personal/openclaw/docker-compose.yml exec openclaw-gateway \
  node dist/index.js config get browser.executablePath
```

5. Enable headless mode (no display server needed inside containers):

```bash
docker compose -f ~/src/personal/openclaw/docker-compose.yml exec openclaw-gateway \
  node dist/index.js config set browser.headless true
```

Verify:

```bash
docker compose -f ~/src/personal/openclaw/docker-compose.yml exec openclaw-gateway \
  node dist/index.js config get browser.headless
```

6. Disable Chrome's sandbox (required inside containers):

```bash
docker compose -f ~/src/personal/openclaw/docker-compose.yml exec openclaw-gateway \
  node dist/index.js config set browser.noSandbox true
```

Verify:

```bash
docker compose -f ~/src/personal/openclaw/docker-compose.yml exec openclaw-gateway \
  node dist/index.js config get browser.noSandbox
```

7. Enable the browser feature:

```bash
docker compose -f ~/src/personal/openclaw/docker-compose.yml exec openclaw-gateway \
  node dist/index.js config set browser.enabled true
```

Verify:

```bash
docker compose -f ~/src/personal/openclaw/docker-compose.yml exec openclaw-gateway \
  node dist/index.js config get browser.enabled
```

8. Disable D-Bus for Chrome (prevents connection errors inside containers):

```bash
docker compose -f ~/src/personal/openclaw/docker-compose.yml exec openclaw-gateway \
  node dist/index.js config set browser.extraArgs '["--disable-features=dbus","--disable-gpu"]' --strict-json
```

How do I do this step?

Open your `docker-compose.yml` file and find the `openclaw-gateway` service. Under its `environment` section, add the following line:

```yaml
DBUS_SESSION_BUS_ADDRESS: /dev/null
```

It should look like this (with your other environment variables):

```yaml
environment:
  HOME: /home/node
  TERM: xterm-256color
  ...
  DBUS_SESSION_BUS_ADDRESS: /dev/null
```

After saving the file, restart the container for changes to take effect:

```bash
docker compose -f ~/src/personal/openclaw/docker-compose.yml restart openclaw-gateway
```

This disables D-Bus for Chrome to avoid connection errors inside the container.

Verify:

```bash
docker compose -f ~/src/personal/openclaw/docker-compose.yml exec openclaw-gateway \
  node dist/index.js config get browser.extraArgs
```

9. Restart the gateway to apply the config:

```bash
docker compose -f ~/src/personal/openclaw/docker-compose.yml restart openclaw-gateway
```

Verify:

```bash
docker compose -f ~/src/personal/openclaw/docker-compose.yml logs --tail 20 openclaw-gateway
```

Should show the gateway starting up without errors.

## Environment Variables

Add environment variables for the DCA bot

Add `RIPIO_EMAIL` and `RIPIO_PASSWORD` to the openclaw `.env` file (located next to `docker-compose.yml` in the openclaw repo):

```bash
## Ripio (DCA bot)
RIPIO_EMAIL=your-email@example.com
RIPIO_PASSWORD=your-password
```

Then wire them into both services in the openclaw `docker-compose.yml` (`~/src/personal/openclaw/docker-compose.yml`). Add these lines to the `environment` section of both `openclaw-gateway` and `openclaw-cli`:

```yaml
RIPIO_EMAIL: ${RIPIO_EMAIL:-}
RIPIO_PASSWORD: ${RIPIO_PASSWORD:-}
```

After editing `.env` and `docker-compose.yml`, restart the container:

```bash
docker compose -f ~/src/personal/openclaw/docker-compose.yml up -d
```

Verify they're set:

```bash
docker exec openclaw-openclaw-gateway-1 env | grep RIPIO
```

## Deploying Skills

Copy the skill folder contents (note the `/.` source and trailing `/` destination to avoid nesting):

```bash
docker cp ~/src/personal/a-dca-bot/skills/ripio-login/. openclaw-openclaw-gateway-1:/home/node/.openclaw/workspace/skills/ripio-login/
```

To copy a single file instead:

```bash
docker cp ~/src/personal/a-dca-bot/skills/ripio-login/SKILL.md \
  openclaw-openclaw-gateway-1:/home/node/.openclaw/workspace/skills/ripio-login/SKILL.md
```

## Editing Files in the Container

```bash
  # Copy out
  docker cp openclaw-openclaw-gateway-1:/home/node/.openclaw/openclaw.json ./openclaw.json

  # Edit it locally, then copy back
  docker cp ./openclaw.json openclaw-openclaw-gateway-1:/home/node/.openclaw/openclaw.json
```
