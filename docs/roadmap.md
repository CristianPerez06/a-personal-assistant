# Roadmap — making a-personal-assistant extensible by non-devs

This document tracks the multi-milestone effort to grow the repo from "one developer maintaining the Ripio DCA skill" into "friends and family can author and run their own automations." It's a working doc — update it as milestones land or scope shifts.

## Context

The repo today automates Ripio DCA, authored entirely by the project's developer. The goal is to make adding new browser-automation skills (logins, recurring buys, balance checks, anything otherwise done by hand) feasible for non-devs in our trust circle, without rewriting it into a hosted multi-tenant service first.

The chosen contributor loop is:

1. **Record** the flow with Playwright's `codegen` on the contributor's host (visible browser).
2. **Translate** the recording into an OpenClaw skill by pasting it into a Claude conversation along with a templated prompt that encodes this repo's conventions.
3. **Install** the generated skill into the contributor's own OpenClaw container and try it.
4. **PR** if shareable.

Playwright is a contributor tool only — not an OpenClaw runtime dep. The skills run via `openclaw browser`.

## Milestones

### M1 — Docs + scaffolding (DONE)

Goal: make the codegen→Claude→install loop reliably work end-to-end with the existing Docker setup. No new runtime deps, no recorder build, no LLM CLI.

Shipped:

- `skills/_template/SKILL.md` — frontmatter + section-structure skeleton.
- `skills/_template/scripts/_template.sh` — shebang + `set -e` + `openclaw browser start` + helpers (`js_escape`, `fill_by_id`, `click_by_id`, `wait_for_url_stable`) lifted from `skills/ripio-login/scripts/ripio-login.sh`.
- `prompts/skill-from-codegen.md` — the load-bearing prompt. Encodes: frontmatter shape, body section order, exit-code conventions (0/1/2/3/4/5), React-safe input fill rationale, mandatory `Failure Handling` block, "things to strip from codegen output" checklist, branching-flow guidance, reference-skill pointers.
- `docs/recording-a-skill.md` — non-dev walkthrough from `npx playwright codegen` through `docker cp` install, with iterate/share steps.
- `README.md` — full rewrite from one-line stub. Covers prerequisites, quick start, running existing skills, authoring new ones, deploying, env-var convention, project layout, security model, troubleshooting.
- `CLAUDE.md` — added `_template/`, `docs/`, `prompts/` to project map; added "Contributing a New Skill" section that routes future Claude sessions through the documented workflow.

Verified:

- `bash -n skills/_template/scripts/_template.sh` syntax-checks clean.
- `skills/_template/SKILL.md` frontmatter parses and contains all required keys.

#### M1 — verification still pending

Best done in a separate session, since each requires either a fresh Claude conversation or a non-dev tester:

1. **Regression test against `ripio-buy`.** Hand-craft a "fake codegen" `.ts` that mirrors what Playwright would have produced for the existing Ripio buy flow. Run it through the prompt template in a fresh Claude conversation. Diff the generated `SKILL.md` + `scripts/ripio-buy.sh` against the real files in `skills/ripio-buy/`. Iterate the prompt template on any structural drift (missing sections, wrong exit-code conventions, missing failure-handling block, dropped React-safe setter, etc.). Don't expect a line-for-line match — just shape-equivalence.
2. **Fresh-target end-to-end test.** Pick a small public site (a no-auth form site like httpbin, or a public Notion login page). Record with `npx playwright codegen`. Run through the prompt. Install per `docs/recording-a-skill.md`. Trigger and confirm it works. Acceptable: minor manual fixups. Unacceptable: shape drift the prompt should have prevented — fold any recurring fixups back into `prompts/skill-from-codegen.md`.
3. **Contributor walkthrough.** Have one friend/family member follow the README on a fresh machine without dev help. Anywhere they get stuck is a doc bug. Likely doc-bug surface: env-var setup, the `docker cp` command (container name might differ on their machine), the Claude paste/edit step.

### M2 — Polish the Docker UX + bundled recorder

Goal: turn install into a single command and remove host-side Node from the prerequisites for contributors who don't want to install it.

Open scope, decide when M1 verification is solid:

- **Single `docker run` UX** — extract this repo's Docker config so a contributor can install with one command rather than cloning two repos and editing two compose files. Possibly a published image on GHCR with this repo's skills baked in plus a writable `skills/` volume mount.
- **Bundled recorder mode** — `docker compose run --rm recorder <url>` that launches Playwright codegen inside the container with X11 forwarding (or via a remote-browser-debug session the contributor opens in their local browser). Avoids the host-side `npx playwright` step.
- **Optional LLM CLI wrapper** — `bun run new-skill < codegen.ts` that wraps `prompts/skill-from-codegen.md` + the Anthropic API and writes the skill directory directly. Saves the chat paste step for contributors with an API key. Strictly optional; the chat-paste path remains supported.
- **Per-service env-var conventions** — once we have >2 services (Ripio + something else), nail down the `<SERVICE>_<FIELD>` convention in docs and have the README's troubleshooting block know about it.

Decision to defer until M1 verification: whether M2 needs its own roadmap entry per item or can ship as one cohesive "v2 install experience" push.

### M3 — Multi-tenant Coolify (or similar) deployment

Goal: friends/family can use the assistant without running anything locally. They talk to a hosted gateway and skills run there.

**This is a much bigger jump than M1→M2 — security and ops dominate.** Do not plan implementation until the open questions below have explicit answers:

- **Credential model.** Shared exchange creds across all users (low utility — why would they use it?) vs each user storing their own creds on your server (you become a credential aggregator with breach blast radius, plus key-rotation and encryption-at-rest concerns). Or per-user-bring-your-own via OAuth where the service supports it.
- **Sandboxing between users.** A misbehaving or malicious skill from user A must not be able to see user B's session, env vars, or browser state. One shared OpenClaw container is unsafe. Per-user containers? Per-user browser profiles? Per-user gateways behind a router?
- **Auth + identity.** How does a user prove they're allowed to talk to the hosted gateway? Telegram bot per user (auth tied to Telegram identity), web app with login, allowlisted API keys, something else? Recovery flow when someone loses access?
- **Exchange ToS / KYC.** Automating exchange logins on someone else's behalf has legal implications that vary by exchange and jurisdiction. Specifically check Ripio's ToS for delegated automation; check whether running their flow from a non-residential cloud IP triggers risk scoring.
- **Operational responsibilities.** Who's oncall when a skill silently misbehaves against someone's real exchange account? What logging is in place? Who can audit?
- **Threat model document.** Before any M3 code: explicit STRIDE-style pass on the above. Treat M3 as needing its own plan with its own approval, not just "deploy M2's image to Coolify."

### Parked — Custom OpenClaw recorder

The "build a Playwright-codegen-like recorder native to OpenClaw" idea. Out of scope until codegen+LLM translation visibly hits a quality ceiling — define that as: ≥5 contributed skills, ≥30% of them needing material manual edits after Claude's output. If we get there, revisit; until then, the cost (selector heuristics, autowait, shadow DOM, iframe handling — all things Playwright has years of investment in) doesn't pay back for our audience size.

## How to resume

When picking this back up:

1. Read this file's M1 verification section. If anything there is still pending, do it before starting M2 — M2's design depends on whether the prompt template is actually doing its job.
2. If M1 verification surfaces recurring fixups Claude has to make to the codegen output, fold them into `prompts/skill-from-codegen.md` first, then re-run the regression test.
3. For M2, decide install-experience scope (single image vs published image vs bundled recorder vs LLM CLI) before designing — they're independent choices and not all of them have to ship together.
4. For M3, do not start with code. Start with the threat model. Get explicit answers (even "we accept this risk and here's why") for each open question in the M3 section above.

## Related artifacts

- `prompts/skill-from-codegen.md` — the LLM prompt; ground truth for skill conventions.
- `skills/_template/` — the skeleton; demonstrates the conventions in working form.
- `docs/recording-a-skill.md` — the contributor-facing walkthrough.
- `~/.claude/plans/we-already-have-this-fizzy-breeze.md` — the pre-implementation plan from the session that built M1. Captures the design rationale that led here.
