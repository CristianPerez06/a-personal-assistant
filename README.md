# a-personal-assistant

Your own personal assistant, running on your Mac. It can log into websites, perform recurring tasks (buying crypto on a schedule, checking balances, anything you'd otherwise do by hand), and you talk to it through a local dashboard or a Telegram bot. Built on [OpenClaw](https://github.com/openclaw/openclaw).

Everything runs **on your machine**. Your passwords and API keys never leave it.

## Quick start

```bash
git clone https://github.com/cristianperez06/a-personal-assistant.git
cd a-personal-assistant
./bootstrap.sh
```

That's it. The script installs everything it needs (Homebrew, Node, Docker Desktop, Chromium) and walks you through configuration. When it finishes, the dashboard opens at <http://127.0.0.1:18789/>.

> Currently macOS only (Intel and Apple Silicon).
> Re-running `./bootstrap.sh` is safe — it skips anything already done.

## What you'll be asked for

The script will prompt you for the following. You can skip the optional ones and add them later by editing `.env`.

| | What | Where to get it |
|---|---|---|
| Required | An **LLM API key** | [OpenAI](https://platform.openai.com/api-keys), [OpenRouter](https://openrouter.ai/keys), or [NVIDIA](https://build.nvidia.com/) — pick one |
| Optional | A **Telegram bot token** | [@BotFather](https://t.me/BotFather) on Telegram. Without it, you use the dashboard only. |
| Optional | **Ripio credentials** | Only if you want to use the bundled `ripio-login` / `ripio-buy` / `ripio-dca` skills. |

The dashboard pairing token is generated for you and stored in `.env`.

## Using it

Open the dashboard at <http://127.0.0.1:18789/> and just talk to it in plain language:

- *"Run my DCA"* → invokes the `ripio-dca` skill (login + buy)
- *"Buy the dip on Ripio with my available balance"* → same skill
- *"Log in to Ripio"* → invokes `ripio-login` directly

Each skill describes itself in plain English; the agent picks the right one from what you say. If a skill needs information you haven't given it (e.g. a 2FA code), it'll ask at the right moment.

## Day-to-day commands

```bash
docker compose down                          # stop
docker compose up -d                         # start
docker compose logs -f                       # tail logs
docker compose pull && docker compose up -d  # update to the latest image
```

If anything gets stuck, just re-run `./bootstrap.sh` — it'll repair whatever's broken without redoing what's already working.

## Adding your own automations

You don't need to write code. The workflow:

1. **Record** the flow you want to automate by running `npx playwright codegen <url>` (Playwright was installed by `bootstrap.sh`). Click through the steps in the browser that opens — Playwright records your clicks as a script.
2. **Translate** the recording into a skill by pasting it into a Claude conversation along with the template prompt in [`prompts/skill-from-codegen.md`](prompts/skill-from-codegen.md).
3. **Drop the result** into `skills/<your-skill-name>/`. The container picks it up automatically on the next start (or run `docker compose restart`).

The full walkthrough is in [`docs/LEGACY_recording-a-skill.md`](docs/LEGACY_recording-a-skill.md) — still mostly accurate, slated for a refresh.

## Privacy & safety

- Your `.env` (passwords, API keys) lives only on your Mac. Nothing is uploaded anywhere.
- Skills only run when you trigger them through your own dashboard or bot.
- The dashboard is bound to `127.0.0.1` — it isn't reachable from your LAN or the internet.

Multi-user / hosted deployment is **out of scope**. If you fork this for that purpose, you're on your own for credential isolation, sandboxing, and the threat model that comes with it.

## When something breaks

- **`./bootstrap.sh` failed partway** → just re-run it. Steps that already worked are skipped.
- **Docker Desktop won't start** → open it manually from Applications, accept any GUI prompts, then re-run `./bootstrap.sh`.
- **Dashboard says "token mismatch"** → your `.env` and the container disagree. `docker compose down && docker compose up -d` usually fixes it; if not, regenerate the token (delete `OPENCLAW_GATEWAY_TOKEN=…` from `.env` and re-run `./bootstrap.sh`).
- **Anything else** → `docker compose logs -f` is the first place to look.

## Legacy documentation

The original developer-only docs are kept temporarily under `LEGACY_*` filenames while the new flow stabilises:

- `LEGACY_README.md` — the previous README (manual Docker + sibling OpenClaw repo)
- `LEGACY_openclaw-instructions.md` — original OpenClaw setup notes
- `LEGACY_openclaw-docker-instructions.md` — extended Docker notes
- `docs/LEGACY_recording-a-skill.md` — skill authoring walkthrough

They'll be removed once nothing relies on them.
