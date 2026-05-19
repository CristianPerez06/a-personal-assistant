---
name: _template
description: TEMPLATE — copy this directory to `skills/<your-skill-name>/` and edit. Replace this description with a single paragraph that tells the agent (a) what the skill does, (b) when to invoke it (the verbs/phrases a user might say), (c) what env vars it reads, and (d) what state it assumes (e.g. "assumes already logged in"). The agent reads only this `description` field to decide whether to use your skill — be specific.
user-invocable: false
metadata:
  {
    "openclaw":
      { "emoji": "🧩", "requires": { "config": ["browser.enabled"] } },
  }
---

# <Skill Title>

One-line summary of what this skill does.

## Configuration

Required environment variables:

- **`<ENV_VAR_NAME>`** — what it is and an example value.

If any are missing, ask the user for the missing value.

## Running the Script

First, verify env vars are configured:

```bash
echo "<ENV_VAR_NAME>=${<ENV_VAR_NAME>:-NOT_SET}"
```

Then run the script (note the **absolute container path** — skills are deployed to `/home/node/.openclaw/workspace/skills/<name>/`):

```bash
bash /home/node/.openclaw/workspace/skills/<your-skill-name>/scripts/<your-skill-name>.sh
```

Exit codes:

- `0` — success.
- `1` — generic / unexpected error.
- `2` — auth/data error (e.g. bad credentials, insufficient balance).
- `3` — branch needed (e.g. 2FA screen appeared — call back with `--2fa <code>`).
- `4` — branch needed (e.g. magic-link screen appeared — call back with `--magic-link <token>`).
- `5` — unknown post-action state.

Delete the rows you don't need. If you add a new branch, add a new code.

## Failure Handling

**Do not attempt to fix, work around, or retry failures autonomously.** If any
script step fails, stop immediately and report the following to the user:

- The exact command that was run
- The exit code
- The full stderr/stdout output (untruncated)
- The current page URL and a fresh `openclaw browser snapshot`, if a browser
  is involved

Do not edit the script. Do not try alternate selectors, alternate commands,
direct browser launches, or other "creative" workarounds. Do not retry. Do
not change the OpenClaw config. The user will investigate and direct any fix.

## Post-<Action>

Describe what state the browser is left in after a successful run (e.g.
"signed in, on the dashboard, modals dismissed"). The next skill or the user
will pick up from here.
