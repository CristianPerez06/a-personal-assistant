# a-personal-assistant

A personal assistant built on [OpenClaw](https://github.com/openclaw/openclaw). Add browser-automation skills (logins, recurring buys, balance checks, anything you'd otherwise do by hand) and trigger them through an OpenClaw-connected interface (dashboard, Telegram bot, etc.).

This repo is designed to be **forked and run locally** — your credentials never leave your machine.

## What's here

- **Browser-automation skills** under `skills/`. Each one is a small folder with a `SKILL.md` (describes what it does and when to use it) and a `scripts/` directory (the bash + JS that drives the browser via OpenClaw).
- **Currently shipped skills:**
  - `ripio-login` — automates Ripio login including 2FA and magic-link verification.
  - `ripio-buy` — buys the configured asset with the maximum available fiat balance.
  - `ripio-dca` — orchestrator: runs `ripio-login` then `ripio-buy` end-to-end.
- **A workflow for adding new skills** without writing code by hand — see [Authoring a new skill](#authoring-a-new-skill) below.

## Prerequisites

- **Docker Desktop** — [docs.docker.com/desktop](https://docs.docker.com/desktop/)
- **The OpenClaw repo** cloned at `~/src/personal/openclaw/` (the `docker-compose.yml` in this repo extends OpenClaw's compose file via that path):

  ```bash
  git clone https://github.com/openclaw/openclaw.git ~/src/personal/openclaw
  ```

- **Node.js 20+** on your host — only needed if you plan to author new skills (for Playwright's recorder). Not required to just run existing skills.

## Quick start

```bash
# 1. Clone this repo
git clone <this-repo-url> a-personal-assistant
cd a-personal-assistant

# 2. Configure credentials
cp .env.example .env
# Edit .env — fill in OPENCLAW_GATEWAY_TOKEN, LLM_API_KEY, RIPIO_EMAIL, etc.

# 3. Start the OpenClaw gateway
docker compose -f ~/src/personal/openclaw/docker-compose.yml up -d

# 4. Deploy this repo's skills into the running container
docker cp skills/. openclaw-openclaw-gateway-1:/home/node/.openclaw/workspace/skills/
```

Open the dashboard at [http://localhost:18789/](http://localhost:18789/) to interact with the agent.

If the gateway rejects you with a token-mismatch error, or you need to set browser config / install Chromium, follow the detailed setup in **[`openclaw-instructions.md`](openclaw-instructions.md)**.

## Running an existing skill

The shipped skills are user-invocable — ask the agent in natural language. Examples:

- `ripio-dca`: *"Run my DCA"*, *"Buy the dip on Ripio with my available balance"*
- `ripio-login` (rarely used directly): *"Log in to Ripio"*
- `ripio-buy` (assumes you're already logged in): *"Buy the configured asset on Ripio"*

The agent reads each skill's `description` from its `SKILL.md` frontmatter and picks the right one based on what you say.

If the skill needs an env var you haven't set, the agent will ask. If a step is interactive (2FA code, magic-link token), it'll prompt at the right moment.

## Authoring a new skill

You don't need to write code. The workflow is:

1. **Record** the flow you want to automate using Playwright's built-in recorder (`npx playwright codegen <url>`).
2. **Translate** the recording into a skill by pasting it into a Claude conversation along with a templated prompt that knows this repo's conventions.
3. **Install** the generated skill into your local OpenClaw container and try it.

The end-to-end walkthrough is in **[`docs/recording-a-skill.md`](docs/recording-a-skill.md)**. The templated prompt is in **[`prompts/skill-from-codegen.md`](prompts/skill-from-codegen.md)**.

If you'd rather start from a hand-edited skeleton, copy `skills/_template/` to `skills/<your-name>/` and fill in the placeholders. The template's `scripts/_template.sh` includes the helpers (`fill_by_id`, `click_by_id`, `wait_for_url_stable`) that handle the tricky parts of React-app automation.

## Deploying a skill to the container

After you create or edit a skill on your host, copy it into the running gateway:

```bash
# Deploy the whole skill directory
docker cp skills/<skill-name> openclaw-openclaw-gateway-1:/home/node/.openclaw/workspace/skills/

# Or just one file
docker cp skills/<skill-name>/SKILL.md openclaw-openclaw-gateway-1:/home/node/.openclaw/workspace/skills/<skill-name>/SKILL.md
```

The container picks up changes on the next skill invocation; no restart needed.

## Environment variables

See `.env.example` for the full list. The variables specific to the shipped skills:

- `RIPIO_EMAIL`, `RIPIO_PASSWORD` — Ripio account credentials (used by `ripio-login`).
- `RIPIO_DCA_ASSET_ORIGIN` — source currency for DCA buys, e.g. `ARS`.
- `RIPIO_DCA_ASSET_TARGET` — ticker of the asset to buy, e.g. `BTC`.

New skills you author should follow the same naming convention: `<SERVICE>_<FIELD>` (uppercase, underscored).

## Project layout

```
.
├── README.md                    — this file
├── CLAUDE.md                    — instructions for Claude when working in this repo
├── .env.example                 — env var template
├── docker-compose.yml           — extends OpenClaw's compose with this repo's env vars
├── openclaw-instructions.md     — detailed OpenClaw setup reference
├── openclaw-docker-instructions.md — extended Docker setup notes
├── docs/
│   └── recording-a-skill.md     — how to author a new skill (Playwright codegen → Claude → install)
├── prompts/
│   └── skill-from-codegen.md    — the LLM prompt template used by the workflow above
└── skills/
    ├── _template/               — skeleton + helper functions for new skills
    ├── ripio-login/
    ├── ripio-buy/
    └── ripio-dca/
```

## Security model

This is a single-user, local-only setup by design:

- Your credentials live in your local `.env` and the running container's environment. They are never uploaded anywhere.
- Skills only run when you trigger them through your local OpenClaw instance.
- The container is bound to localhost; the dashboard requires the token in `OPENCLAW_GATEWAY_TOKEN`.

Multi-user / hosted deployment is out of scope for this repo. If you fork it for that purpose, you're responsible for credential isolation, per-user sandboxing, and the rest of the threat model that comes with multi-tenant credential handling.

## Troubleshooting

- **"browser is not running" mid-skill** — every script in this repo starts with `openclaw browser start >/dev/null` to prevent this. If you see it in a new skill, make sure that line is present.
- **`docker cp` says destination doesn't exist** — the gateway container's skills directory is created on first run. Make sure `docker compose ... up -d` completed before copying.
- **Token mismatch on the dashboard** — set `OPENCLAW_GATEWAY_TOKEN` in `.env` and restart the gateway. Details in `openclaw-instructions.md`.
- **Chromium / browser-stack errors** — follow the "Browser Setup" section of `openclaw-instructions.md`. The same doc covers the rare Playwright-Chromium-version-changed case.
- **Anything else** — open an issue or read `openclaw-instructions.md`'s troubleshooting blocks; they cover most setup edge cases.
