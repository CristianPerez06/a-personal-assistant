# a-personal-assistant

A personal assistant built on OpenClaw. Uses OpenClaw's browser automation and skills system; current capabilities include automating Ripio exchange operations (DCA / login / buy).

## Project Structure

- `skills/` — OpenClaw skills deployed to the gateway container
  - `_template/` — skeleton for new skills, with reusable helpers (`fill_by_id`, `click_by_id`, `wait_for_url_stable`) in `scripts/_template.sh`
  - `ripio-login/` — Automated Ripio login flow (email/password + 2FA + magic link)
  - `ripio-buy/` — Single buy action: buys the configured asset with the max available balance. Assumes logged in.
  - `ripio-dca/` — Orchestrator (markdown only): invokes `ripio-login` then `ripio-buy` for the full DCA flow.
- `docs/recording-a-skill.md` — Contributor walkthrough: Playwright codegen → LLM translation → installed skill
- `prompts/skill-from-codegen.md` — The templated LLM prompt used by the workflow above; encodes every skill convention this repo follows
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
- `RIPIO_DCA_ASSET_ORIGIN` — source currency for the DCA buy (e.g. `ARS`)
- `RIPIO_DCA_ASSET_TARGET` — ticker of the asset the DCA skill should buy (e.g. `BTC`)

These are passed to both `openclaw-gateway` and `openclaw-cli` services via docker-compose.

## Contributing a New Skill

When a user asks for help adding a new automation (or a non-dev contributor asks how to add one), route them through the documented workflow rather than hand-writing the skill from scratch:

1. Point them at `docs/recording-a-skill.md` for the end-to-end walkthrough.
2. The translation step uses `prompts/skill-from-codegen.md` — that prompt already encodes every convention this repo follows (frontmatter shape, exit-code conventions, the React-safe `fill_by_id` pattern, `Failure Handling` boilerplate, etc.). Reuse it instead of paraphrasing.
3. New skills should start from `skills/_template/` (copy the directory, rename, fill in placeholders) so they pick up the helper functions without copy-paste drift.

If you're authoring a skill directly (without the codegen workflow), still follow `skills/_template/` and the conventions documented in the prompt template — they're load-bearing for the agent's ability to invoke skills correctly.

## Development Notes

- For local development, run `openclaw gateway run` directly on the host instead of using Docker (avoids origin/networking issues).
- Docker deployment requires `gateway.controlUi.allowedOrigins` to be configured. See `openclaw-instructions.md` for details.
- Browser automation requires Chromium installed inside the container. See the "Browser Setup" section in `openclaw-instructions.md`.
