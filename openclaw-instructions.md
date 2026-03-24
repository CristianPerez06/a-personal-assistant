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

4. Install dependencies for Chromium and Playwrght

```bash
docker compose -f ~/src/personal/openclaw/docker-compose.yml exec -u root openclaw-gateway \
  bash -c "apt-get update && apt-get install -y \
    libnspr4 libnss3 libatk1.0-0 libatk-bridge2.0-0 \
    libdbus-1-3 libcups2 libxkbcommon0 libatspi2.0-0 \
    libxcomposite1 libxdamage1 libxfixes3 libxrandr2 \
    libgbm1 libasound2"
```

5. Install Chromium and Playwright

```bash
docker compose exec openclaw-gateway bash -c "npx playwright install chromium"
```

6. Copy the SKILL folder

```bash
docker cp <PATH-TO-YOUR-SKILL-FOLDER> <DOCKER-CONTAINER-NAME>:/home/node/.openclaw/workspace/skills/
```

7. If you want to only copy one file use:

```bash
docker cp ~/src/personal/a-dca-bot/skills/ripio-login/SKILL.MD \
  openclaw-openclaw-gateway-1:/home/node/.openclaw/workspace/skills/ripio-login/SKILL.md
```
