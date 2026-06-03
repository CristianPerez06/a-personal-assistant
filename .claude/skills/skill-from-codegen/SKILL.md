---
name: skill-from-codegen
description: Convert a Playwright codegen recording into a new OpenClaw skill in this repo. Gathers context from the user, maps every `REPLACE_WITH_*` placeholder to a `<SHORT_SKILL_NAME>__<SUFFIX>` env var, and writes the SKILL.md + bash script under `skills/<skill-name>/`. Use when the user pastes or points to a codegen `.ts`/`.js` file and wants it turned into a skill — phrasings like "turn this codegen into a skill", "build a skill from this recording", "scaffold the X skill from this file".
user_invocable: true
allowed-tools: Read, Write, Bash, AskUserQuestion
---

# Skill from codegen

Translate a Playwright codegen recording into an OpenClaw skill that follows this repo's conventions. The codegen is a *starting point* — strip its Playwright wrapper, replace its placeholder strings with env-var reads, and emit a skill directory under `skills/`.

## Steps

### 1. Locate the codegen input

If the user already pointed at a file path, use it. Otherwise ask:

- If only one `.ts`/`.js` file at the repo root looks like a codegen output (top-level IIFE, `chromium.launch`, `page.getByRole`), offer it as the default.
- Otherwise ask the user to paste the path or the file contents.

Read the file. Confirm it looks like codegen output (presence of `await page.` calls, `REPLACE_WITH_` tokens, or a `chromium.launch` block). If it doesn't, stop and ask the user.

### 2. Gather context via `AskUserQuestion`

Ask the user, in this order — one question per `AskUserQuestion` call, *unless* you can confidently infer the answer from the codegen + filename + the user's original message, in which case skip the question and state your inference. You may batch into a single `AskUserQuestion` call only when none of the answers depend on each other.

1. **Skill name** (kebab-case, becomes the directory name and file name). Suggest one based on the codegen filename or target site. Validate: lowercase, hyphens only, no spaces. The **short name** used for env-var prefixes is this string upper-cased with hyphens → underscores. Example: `generate-invoice` → `GENERATE_INVOICE`.
2. **Skill purpose** — one paragraph: what it does, when to invoke it, what state it assumes (e.g. "assumes already logged in via `<other-skill>`"). This is what the agent reads to decide whether to use the skill. Be specific.
3. **Branching / interactive notes** — anything the recording can't show: "may show a 2FA screen", "may ask for a magic-link token", "stop if button text says 'Closed'", etc. If the flow is purely linear, allow an empty answer.

### 3. Classify each `REPLACE_WITH_*` token: env var or runtime prompt

Scan the codegen for every distinct `REPLACE_WITH_<SUFFIX>` token. Deduplicate — a token that appears multiple times in the codegen is one value, not two.

For each distinct token, build two candidate names:

- **Env-var name**: `<SHORT_SKILL_NAME>__<SUFFIX>`, uppercase, **double underscore** between the short name and the suffix.
  - Example with skill `generate-invoice`: `REPLACE_WITH_FROM_ID` → `GENERATE_INVOICE__FROM_ID`.
- **Flag-arg name**: `--<suffix-kebab>`, lowercase, hyphen-separated.
  - Example: `REPLACE_WITH_FROM_ID` → `--from-id`.

Then ask the user, **for each token**, how the generated skill should receive that value:

- **Env var** (default) — set once in `.env`, no per-run typing. Best for values that rarely change (sender name, your tax id).
- **Runtime prompt** — agent asks the user every time the skill runs, passed in as a flag arg. Best for values that change per run (invoice number, date, dollar amount).

**Batch the questions in groups of 4** via a single `AskUserQuestion` call (the tool allows 1–4 questions per call). For ≤4 tokens, one call; for more, chain calls of 4 until done. Use this question shape per token:

- **Question**: `How should <ORIGINAL_TOKEN> be supplied?`
- **Header**: a short label derived from the suffix (e.g. `From ID`, 12 chars max).
- **Options** (env-var first):
  1. `Env var: <SHORT_SKILL_NAME>__<SUFFIX>` — read from .env at run time.
  2. `Runtime prompt: --<suffix-kebab>` — agent asks the user each run.

Record the answer per token. Do **not** ask a renaming follow-up — auto-generated names are deterministic, and the user can rename in-file post-generation if they want.

If the codegen has no `REPLACE_WITH_` tokens at all, the recording was unmodified — stop and tell the user: "this codegen has no `REPLACE_WITH_` placeholders; edit the recording to mark which fields should be parameterized, then re-run the skill." Do not guess at which raw literals to extract.

### 4. Translate the codegen to a bash script

Produce `skills/<skill-name>/scripts/<skill-name>.sh`. **Hard rules** — every one is load-bearing:

- `#!/usr/bin/env bash` shebang, then a comment block listing usage + exit codes, then `set -e`.
- First runnable line: `openclaw browser start >/dev/null` (idempotent — prevents false "browser not running" errors between separate invocations).
- Copy the three helpers **verbatim** from `skills/_template/scripts/_template.sh`: `js_escape`, `fill_by_id`, `click_by_id`, `wait_for_url_stable`. Don't paraphrase them.
- Drop these Playwright patterns:
  - `import { test, expect } …` / `test('...', async ({ page }) => { ... })` wrapper — gone.
  - `chromium.launch` / `browser.newContext` / `context.newPage` boilerplate — gone.
  - `await page.goto(URL)` → `openclaw browser navigate "$URL"`.
  - `await page.locator(...).click()` and `getByRole(...).click()` → `click_by_id "<id>"` whenever a stable `id` or `data-testid` exists. If the recording used text-content / role / class selectors, **stop and ask the user to inspect the page for stable ids** — do not silently fall back to brittle selectors. If no stable id exists at all, fall back to an inline `openclaw browser evaluate` with `querySelector`, and call this out in the SKILL.md `## Failure Handling` section as a fragile selector.
  - `await page.locator(...).fill(value)` / `getByRole(...).fill(value)` → `fill_by_id "<id>" "$<ENV_VAR>"`.
  - `await page.waitForTimeout(ms)` → either `wait_for_url_stable` (after navigation) or polling `openclaw browser evaluate` for a specific element. **Never** preserve raw `sleep`.
  - `await page.waitForURL(...)` → `wait_for_url_stable` plus an explicit URL check.
- **Use the React-safe value setter** for every input fill — that is what `fill_by_id` already does. Do not inline a plain `el.value = X`; it bypasses React's tracker and the page silently keeps stale state.
- **Bundle into a single `openclaw browser evaluate`** when consecutive actions must land in the same render frame (TOTP submit, expiring tokens, etc.). Each round-trip to OpenClaw costs 1–3s.
- **Replace every `REPLACE_WITH_*` token with the chosen binding from step 3:**
  - Env-var tokens become `"$<ENV_VAR>"` reads.
  - Runtime-prompt tokens become bash variables set from flag args parsed at the top of the script. Add an `arg --from-id` parser block (a simple `while [[ $# -gt 0 ]]; do case "$1" in --from-id) FROM_ID="$2"; shift 2;; ... esac; done` loop) and validate every runtime-prompt arg was provided — exit `2` with a clear message if any is missing.
  - Any other literal that the recording captured from typed input (the user's email, password, dollar amounts the user typed but didn't mark with `REPLACE_WITH_`) — leave as-is. The convention is: only `REPLACE_WITH_*` tokens get parameterized. If you spot an unparameterized literal that *looks* sensitive, flag it as a TODO in the report, don't silently extract it.
- URLs that never change can stay hardcoded.
- If the recording opens a popup, triggers a download, or closes pages at the end, translate that intent — don't ignore it. Downloads need `openclaw browser evaluate` to read the file location; popups need an explicit URL check.

### 5. Translate to SKILL.md

Produce `skills/<skill-name>/SKILL.md` following this shape exactly:

**Frontmatter** (YAML):

```yaml
---
name: <skill-name>
description: <single paragraph: what it does, the verbs/phrases a user might say to invoke it, the env vars it reads, the state it assumes>
user-invocable: true
metadata:
  {
    "openclaw":
      { "emoji": "<one relevant emoji>", "requires": { "config": ["browser.enabled"] } },
  }
---
```

Note the frontmatter key is `user-invocable` (hyphen), not `user_invocable`. This matches the OpenClaw runtime convention; Claude Code skills use the underscore form. They are different consumers.

**Body sections**, in this order:

1. `# <Skill Title>` and a one-line summary.
2. `## Configuration` — list every **env-var** token (from step 3) as ``- **`<VAR>`** — what it is and an example value.`` End with: "If any are missing, ask the user for the missing value." Omit this section entirely if step 3 produced zero env-var tokens.
3. `## Runtime Inputs` — list every **runtime-prompt** token (from step 3) as ``- **`--flag-name`** — what to ask the user for, and an example value.`` End with: "Ask the user for each of these before invoking the script and pass the answers as flag args." Omit this section entirely if step 3 produced zero runtime-prompt tokens.
4. `## Running the Script` — show the env-var verification first (for the env vars only), then the invocation with **all** flag args present. Use the **absolute container path**:

   ```bash
   echo "<VAR1>=${<VAR1>:-NOT_SET}"
   echo "<VAR2>=${<VAR2>:-NOT_SET}"
   ```

   ```bash
   bash /home/node/.openclaw/workspace/skills/<skill-name>/scripts/<skill-name>.sh \
     --flag-one "<value collected from user>" \
     --flag-two "<value collected from user>"
   ```

   Number multi-step flows. If there are no runtime-prompt args, drop the trailing backslashes and flags.
5. **Exit code list**:
   - `0` success
   - `1` generic / unexpected error
   - `2` auth/data/missing-input error (missing env var, missing required `--flag`)
   - `3`, `4`, … one per branch needed (different code per branch so the agent can dispatch)
   - `5` unknown post-action state
   Drop codes that don't apply.
6. `## Failure Handling` — copy this **verbatim** from `skills/_template/SKILL.md` (the "Do not attempt to fix…" block). Adjust only the wording around what's being automated. Do not soften it.
7. `## Post-<Action>` — what state the browser is left in after a successful run.

### 6. Branching flows

If the user's branching notes mention 2FA, magic links, conditional confirmation modals, etc.:

- Each branch is a separate invocation mode via flag args (e.g. `--2fa <code>`, `--magic-link <token>`). Mirror `skills/ripio-login/scripts/ripio-login.sh`.
- Each branch gets a distinct exit code on the *initial* run, so the agent knows which mode to call back into.
- Document every branch in the SKILL.md `## Running the Script` section as a numbered step ("Step 2 — Enter 2FA code (only if Step 1 exited with code 3)").
- Do **not** require the branch input upfront. Don't prompt for a 2FA code unless 2FA actually came up.

### 7. Write the files

Create the directory tree under `skills/<skill-name>/`:

```
skills/<skill-name>/
├── SKILL.md
└── scripts/
    └── <skill-name>.sh
```

Use `Write` for each file. After both files are written:

```bash
chmod +x skills/<skill-name>/scripts/<skill-name>.sh
```

### 8. Report

Tell the user:

- The two files you created (paths only).
- The **env-var** list they now need to add to `.env` — formatted as a copy-pasteable block (omit this block if there are no env-var tokens):

  ```
  <VAR1>=
  <VAR2>=
  ```
- The **runtime-prompt** flag args the agent must collect before invoking the skill — formatted as a checklist (omit if there are no runtime-prompt tokens):

  ```
  --flag-one  <what to ask for>
  --flag-two  <what to ask for>
  ```
- Any TODOs the recording didn't give you enough information to resolve (e.g. "couldn't find a stable id for the confirm button — verify `#confirm_submit` exists or update the script with the real id", "the download path after the popup is unknown — script currently logs and exits 5").
- A reminder to test with `docker cp skills/<skill-name> a-personal-assistant:/home/node/.openclaw/workspace/skills/` if the container is already running.

Do **not** commit, run, or invoke the new skill. This skill only authors.

## Reference skills

When in doubt, mirror these:

- `skills/ripio-login/` — multi-step interactive flow with 2FA + magic-link branches, exit-code dispatch, bundled fill+submit for TOTP, URL polling, modal cleanup. The canonical example for branching skills.
- `skills/ripio-buy/` — single linear flow with an `--inspect` debug mode and a precondition check (exits 4 if not logged in).
- `skills/ripio-dca/` — markdown-only orchestrator that composes two other skills. Use this shape when the job is "run skill A, then skill B".
- `skills/_template/scripts/_template.sh` — the source of truth for the helper functions. Copy verbatim.
