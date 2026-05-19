# Convert Playwright codegen output → an OpenClaw skill

Paste the entire block below into a Claude conversation, filling in the
`{{...}}` slots with your inputs. Claude will produce a complete skill
directory (`SKILL.md` + `scripts/<skill-name>.sh`) that follows this repo's
conventions.

> If you're a non-dev: don't worry about the bash patterns referenced here —
> just fill in the slots, paste, and review the output. The prompt below tells
> Claude everything it needs to know about how skills are structured.

---

## The prompt (copy from here ⬇️)

You are generating a new skill for the **a-personal-assistant** repo, which runs on top of OpenClaw. I will give you the output of `npx playwright codegen <url>` and you will translate it into an OpenClaw skill following the conventions below.

### Inputs

- **Target site (URL or short name):** `{{TARGET_SITE}}`
- **Skill name (kebab-case, will become the directory name):** `{{SKILL_NAME}}`
- **Skill purpose (one paragraph — what it does, when to invoke it, what state it assumes):** `{{SKILL_PURPOSE}}`
- **Environment variables the skill needs (name + meaning, one per line; use empty string if none):**

```
{{ENV_VARS}}
```

- **Branching / interactive notes (anything the recording can't show — e.g. "may show a 2FA screen", "may ask for a magic-link token", "stop if button text says 'Closed'"; use empty string if the flow is purely linear):**

```
{{BRANCHING_NOTES}}
```

- **Playwright codegen output (paste the entire generated `.ts` file):**

```ts
{{CODEGEN_OUTPUT}}
```

### Required output

Produce **two files**, in two separate fenced code blocks, in this order:

1. ` ```markdown ` block — the full contents of `skills/{{SKILL_NAME}}/SKILL.md`.
2. ` ```bash ` block — the full contents of `skills/{{SKILL_NAME}}/scripts/{{SKILL_NAME}}.sh`.

No prose between or after the blocks unless you have an actual warning the user must see.

### SKILL.md conventions (non-negotiable)

Frontmatter (YAML between two `---` lines):

- `name:` matches the directory name (so: `{{SKILL_NAME}}`).
- `description:` a single paragraph. Must include: what the skill does, the verbs/phrases a user might say to invoke it, the env vars it reads, what state it assumes (e.g. "assumes already logged in via the `<other-skill>` skill"). The agent reads ONLY this field to decide whether to use your skill — be specific.
- `user-invocable: true` for skills an end-user should be able to trigger directly. Set to `false` only for internal helpers.
- `metadata:` exactly this shape (pick a relevant emoji):

```yaml
metadata:
  {
    "openclaw":
      { "emoji": "🧩", "requires": { "config": ["browser.enabled"] } },
  }
```

Body sections, in this order:

1. `# <Skill Title>` then a one-line summary.
2. `## Configuration` — list every required env var as `- **\`VAR_NAME\`** — description`. End with: "If any are missing, ask the user for the missing value."
3. `## Running the Script` — exact bash commands. **Use absolute container paths**: `/home/node/.openclaw/workspace/skills/{{SKILL_NAME}}/scripts/{{SKILL_NAME}}.sh`. If env vars are involved, first show an `echo "VAR=${VAR:-NOT_SET}"` verification line, then the script invocation. Number multi-step flows.
4. **Exit code list** — every code the script can exit with, what it means, what to do next. Conventions:
   - `0` success
   - `1` generic / unexpected error
   - `2` auth/data error (bad credentials, insufficient balance, etc.)
   - `3`, `4` branch-needed states (different code per branch so the agent can dispatch — e.g. 2FA vs magic-link)
   - `5` unknown post-action state
5. `## Failure Handling` — copy this block **verbatim**, adjusting only the wording around what's being automated:

   > **Do not attempt to fix, work around, or retry failures autonomously.** If any script step fails, stop immediately and report the following to the user:
   >
   > - The exact command that was run
   > - The exit code
   > - The full stderr/stdout output (untruncated)
   > - The current page URL and a fresh `openclaw browser snapshot`
   >
   > Do not edit the script. Do not try alternate selectors, alternate commands, direct browser launches, or other "creative" workarounds. Do not retry. Do not change the OpenClaw config. The user will investigate and direct any fix.

6. `## Post-<Action>` — what state the browser is left in after a successful run.

### Script conventions (non-negotiable)

- `#!/usr/bin/env bash` shebang, `set -e` immediately after the header comment.
- First runnable line: `openclaw browser start >/dev/null`. This is idempotent and prevents false "browser not running" errors between separate script invocations.
- **Selectors must use the DOM via `openclaw browser evaluate --fn "..."`**, targeting stable `id` / `data-testid` attributes. Do NOT parse accessibility snapshots with regex — that breaks when the renderer adds attribute markers between the element name and `[ref=...]`.
- **Use the React-safe input fill pattern** for every `<input>`:

  ```js
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
  setter.call(el, '');
  el.dispatchEvent(new Event('input', { bubbles: true }));
  setter.call(el, value);
  el.dispatchEvent(new Event('input', { bubbles: true }));
  el.dispatchEvent(new Event('change', { bubbles: true }));
  ```

  A plain `el.value = X` bypasses React's tracker and the framework keeps stale state. This bites silently — the page looks right but submit does nothing.

- **Always include these three helpers** near the top of the script (copy verbatim from `skills/_template/scripts/_template.sh`): `js_escape`, `fill_by_id`, `click_by_id`. Use them; don't inline `openclaw browser evaluate` calls when one of these fits.
- `click_by_id` already checks `disabled` before clicking. If you click via inline `evaluate`, replicate that check.
- **When timing matters** (e.g. submitting a TOTP code before it expires, or any flow where consecutive actions must happen in the same render frame), **bundle the actions into a single `openclaw browser evaluate` call**. Each round-trip to OpenClaw costs 1–3s; bundling saves both wall time and protects against expiring tokens.
- **For navigation completion, poll the URL until it stabilizes** — don't `sleep N`. Use the `wait_for_url_stable` helper from `skills/_template/scripts/_template.sh`.
- **Credentials and configurable values come from env vars** (`"$RIPIO_EMAIL"`, etc.). NEVER hardcode anything from the codegen recording — emails, passwords, 2FA codes the user typed, search terms, dollar amounts. Replace every such value with an env-var read or a script argument.

### Things to strip from the codegen output

The Playwright codegen output is a starting point, not the deliverable. Drop these patterns:

- `import { test, expect } from '@playwright/test'` and any `test('...', async ({ page }) => { ... })` wrapper.
- `await page.goto(URL)` → `openclaw browser navigate "$URL"` (or hardcode the URL if it never changes).
- `await page.locator(...).click()` → `click_by_id "<id>"` whenever the element has a stable `id` or `data-testid`. If the recording used text-content or CSS class selectors, inspect the page (devtools) and find a stable id/testid before generating the script. If none exists, fall back to an inline `openclaw browser evaluate` with a `querySelector` — and note in the SKILL.md `## Failure Handling` section that this selector is fragile.
- `await page.locator(...).fill(value)` → `fill_by_id "<id>" "$ENV_VAR"`.
- `await page.waitForTimeout(ms)` → either `wait_for_url_stable` (for navigation) or polling `openclaw browser evaluate` for a specific element. Never preserve raw `sleep`.
- `await page.waitForURL(...)` → `wait_for_url_stable` plus an explicit URL check.

### Branching flows

If the user's `{{BRANCHING_NOTES}}` mentions interactive branches (2FA, magic links, confirmation modals that may or may not appear, etc.):

- Implement each branch as a separate invocation mode using flag args (e.g. `--2fa <code>`, `--magic-link <token>`) — see `skills/ripio-login/scripts/ripio-login.sh` in this repo for the canonical pattern.
- Give each branch a distinct exit code (3, 4, ...) on the *initial* run, so the agent knows which mode to call back into.
- Document every branch in the SKILL.md `## Running the Script` section as a numbered step ("Step 2 — Enter 2FA code (only if Step 1 exited with code 3)").
- Do NOT ask the user upfront for inputs that may not be needed (don't prompt for a 2FA code unless 2FA was actually required).

### Reference skills

When in doubt, mirror the style of these existing skills in the repo:

- `skills/ripio-login/` — the most thorough example. Multi-step interactive flow (password → 2FA → magic-link), exit-code-driven dispatch, bundled fill+submit for TOTP, URL polling, modal cleanup. Read its `scripts/ripio-login.sh` for the patterns.
- `skills/ripio-buy/` — single linear flow with an `--inspect` debug mode and a precondition check (errors with code 4 if not logged in).
- `skills/ripio-dca/` — markdown-only orchestrator that composes two other skills. Use this shape when your skill's job is "run skill A, then skill B".

### Output now

Generate the two files. No commentary before the first block. After the second block, list any TODOs the recording didn't give you enough information to resolve (e.g. "couldn't determine a stable selector for the confirm button — verify `#confirm_submit` exists on the page or update the script with the actual id").
