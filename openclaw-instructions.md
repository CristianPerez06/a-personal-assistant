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
docker compose exec openclaw-gateway node dist/index.js devices approve THE_ID_HERE
```
