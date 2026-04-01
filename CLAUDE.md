# a-dca-bot

A DCA (Dollar Cost Averaging) bot built on OpenClaw. Uses OpenClaw's browser automation and skills system to automate Ripio exchange operations.

## Project Structure

- `skills/` — OpenClaw skills deployed to the gateway container
  - `ripio-login/` — Automated Ripio login flow (email/password + 2FA)
- `openclaw-instructions.md` — Setup guide for the OpenClaw Docker environment
- `docker-compose.yml` — Extends the main OpenClaw docker-compose with Ripio env vars

## OpenClaw Gateway

This project uses OpenClaw running in Docker. The main OpenClaw repo lives at `~/src/personal/openclaw/`.

### Running the gateway

```bash
# Start the container
docker compose -f ~/src/personal/openclaw/docker-compose.yml up -d

# Stop
docker compose -f ~/src/personal/openclaw/docker-compose.yml down
```

### Dashboard

Open http://localhost:18789/. If auth is needed:

```bash
docker compose run --rm openclaw-cli dashboard --no-open
```

### Deploying skills to the container

```bash
docker cp skills/ripio-login openclaw-openclaw-gateway-1:/home/node/.openclaw/workspace/skills/ripio-login/
```

### Running CLI commands inside the container

```bash
docker compose -f ~/src/personal/openclaw/docker-compose.yml exec openclaw-gateway node dist/index.js <command>
```

## Environment Variables

Defined in `.env` (see `.env.example`):
- `RIPIO_EMAIL` — Ripio account email
- `RIPIO_PASSWORD` — Ripio account password

These are passed to both `openclaw-gateway` and `openclaw-cli` services via docker-compose.

## Development Notes

- For local development, run `openclaw gateway run` directly on the host instead of using Docker (avoids origin/networking issues).
- Docker deployment requires `gateway.controlUi.allowedOrigins` to be configured. See `openclaw-instructions.md` for details.
- Browser automation requires Chromium installed inside the container. See the "Browser Setup" section in `openclaw-instructions.md`.
