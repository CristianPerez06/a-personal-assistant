# Recording a new skill

This guide walks you through adding a new automation to **a-personal-assistant** without writing any code by hand. The workflow:

1. **Record** the flow you want to automate using Playwright's built-in recorder (`codegen`).
2. **Translate** the recording into an OpenClaw skill by pasting it into a Claude conversation along with a templated prompt.
3. **Install** the generated skill into your local OpenClaw container and try it.
4. **Open a PR** if you'd like to share it.

You do **not** need to know JavaScript, TypeScript, or Bash. You do need to be able to:

- Run a couple of commands in a terminal.
- Open a browser and click through the flow you want to automate.
- Paste text between a chat window and your editor / filesystem.

---

## Prerequisites

- **Node.js 20+** on your host machine. Check with `node --version`. Install from [nodejs.org](https://nodejs.org/) if missing.
- **OpenClaw running locally** via the project's `docker-compose.yml`. See the main [README](../README.md) if you haven't set this up yet.
- A **Claude account** (the recording → skill translation is done by pasting into a Claude conversation — no API key required).

> Playwright is used **only for recording**. It is not an OpenClaw runtime dependency, and the resulting skill does not depend on it. You can uninstall it after recording if you want.

---

## Step 1 — Record the flow

Decide which website and which actions you want to automate. Then on your host (not inside the Docker container), run:

```bash
npx playwright@latest codegen <url>
```

Replace `<url>` with the page you want to start from — for example:

```bash
npx playwright@latest codegen https://app.example.com/login
```

Two windows open:

- **A real browser**, pointed at your URL. Click, type, and navigate exactly as you would to perform the action you want to automate.
- **The Playwright Inspector**, which writes TypeScript code in real time as you interact. Every click and form fill becomes a line of code.

When you're done, hit the red record button to stop, then **copy the entire generated code block** from the Inspector. Save it somewhere — a scratch file is fine.

### What to capture during recording

- **The full happy path** — every click and field, in order, from start to the action you want as the end state.
- **Stable URLs** — start from a deep link (e.g. `/login`) rather than the homepage when possible.

### What to leave out / handle differently

- **Don't type real credentials.** Use a placeholder like `RECORDING_EMAIL` and `RECORDING_PASSWORD` when the form prompts you. You'll tell Claude in the next step that those values should come from env vars, not from the recording.
- **Don't record one-time codes.** Skip 2FA / magic-link / SMS code entries entirely; those branches are handled by telling Claude about them in the prompt's "branching notes" field, not by recording them.
- **Don't record sensitive values you can't get back to.** Anything you type goes into the recording verbatim. When in doubt, use placeholders and tell Claude what the real values represent.

### Multi-page or branching flows

If the site might show different paths depending on its state (e.g. "the cookie banner appears the first time", "the 2FA screen sometimes appears"):

- Record the **simple linear happy path**. One recording, one happy path.
- Make notes about the branches: when they appear, what the user has to provide, what the success state looks like. You'll paste these notes into the prompt's `BRANCHING_NOTES` slot in Step 2.

For each branch, the resulting skill will have a distinct invocation mode (e.g. `--2fa <code>`) and exit code so the agent can dispatch correctly. You don't need to design any of that — Claude does it from your notes.

---

## Step 2 — Translate the recording into a skill

1. Open the prompt template: [`prompts/skill-from-codegen.md`](../prompts/skill-from-codegen.md).
2. Scroll to the section labelled **"The prompt (copy from here ⬇️)"** and copy everything from that point to the end of the file.
3. Open a new Claude conversation.
4. Paste the prompt into the chat. **Before sending**, replace each `{{...}}` slot with your inputs:

   | Slot | What goes here |
   |---|---|
   | `{{TARGET_SITE}}` | e.g. `https://app.example.com` or `Example Bank` |
   | `{{SKILL_NAME}}` | kebab-case directory name, e.g. `example-balance-check` |
   | `{{SKILL_PURPOSE}}` | One paragraph: what it does, when the agent should invoke it, what env vars it needs, what state it assumes. The agent reads only this paragraph to decide whether to use your skill — be specific about the verbs/phrases a user might say ("check my Example Bank balance", "show what's in my account") |
   | `{{ENV_VARS}}` | One per line: `NAME — meaning`. e.g. `EXAMPLE_USERNAME — login email for Example Bank`. Leave blank if none. |
   | `{{BRANCHING_NOTES}}` | Anything the recording can't show. e.g. "may show a 2FA screen with a 6-digit input — call back with `--2fa <code>`". Leave blank if linear. |
   | `{{CODEGEN_OUTPUT}}` | The entire generated TypeScript from Step 1, pasted between the ` ```ts ` fences. |

5. Send. Claude will produce **two fenced code blocks**: the `SKILL.md` and the script.

### What if Claude produces something that doesn't match the format?

Reply asking it to "re-emit both files following the conventions in the prompt exactly — only two fenced blocks, nothing else." The prompt is designed to produce a strict shape; drift usually responds to one nudge.

---

## Step 3 — Install the skill locally

1. On your host, create the skill directory:

   ```bash
   mkdir -p skills/<skill-name>/scripts
   ```

2. Paste the contents of the first fenced block from Claude into `skills/<skill-name>/SKILL.md`.
3. Paste the contents of the second fenced block into `skills/<skill-name>/scripts/<skill-name>.sh`.
4. Make the script executable:

   ```bash
   chmod +x skills/<skill-name>/scripts/<skill-name>.sh
   ```

5. Add any new env vars your skill needs to your `.env` file (next to `docker-compose.yml`).
6. Deploy the skill to the running OpenClaw container:

   ```bash
   docker cp skills/<skill-name> openclaw-openclaw-gateway-1:/home/node/.openclaw/workspace/skills/<skill-name>/
   ```

7. Trigger the skill through OpenClaw (via the dashboard, Telegram bot, or wherever you've wired up your agent).

---

## Step 4 — Iterate

The first run might not work. Common issues and where to look:

- **"selector not found" / `not_found` in the script output** — the recording used a CSS class or text selector that Claude couldn't translate to a stable `id` / `data-testid`. Open the page in devtools, find a stable attribute on the broken element, and edit the script's `click_by_id` / `fill_by_id` calls (or ask Claude to regenerate with the corrected selector).
- **Script exits with code `1` but no clear error** — usually a timing issue. Add a `wait_for_url_stable` call (the helper is defined at the top of the script) after the navigation, or replace a fixed wait with element-existence polling.
- **The action seems to happen but nothing actually changes on the site** — almost always the React input issue. Confirm every `<input>` is filled via `fill_by_id` and not a raw `evaluate` with `el.value = X`. The helper handles this correctly; inline code often doesn't.

If you get stuck, attach the script, the output, and a fresh `openclaw browser snapshot` to a Claude conversation and ask for help diagnosing.

---

## Step 5 — Share (optional)

If your skill is useful to others and doesn't contain anything personal:

1. Make sure no secrets ended up in the script (`grep -i 'password\|token\|@' skills/<skill-name>/`).
2. Open a PR against this repo with your `skills/<skill-name>/` directory.
3. Add an entry to the README's "Available skills" list so others can find it.
