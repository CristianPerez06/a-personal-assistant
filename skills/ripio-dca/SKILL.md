---
name: ripio-dca
description: Runs the full DCA (Dollar Cost Averaging) flow on Ripio end-to-end. Orchestrates the ripio-login skill (handles 2FA / magic-link interactively) and then the ripio-buy skill (buys the configured asset with the max available fiat balance). Use when the user asks to run their DCA, do their recurring buy, invest spare cash on Ripio, or "buy the dip" with the available balance.
user-invocable: true
metadata:
  {
    "openclaw":
      { "emoji": "💸", "requires": { "config": ["browser.enabled"] } },
  }
---

# Ripio DCA (orchestrator)

End-to-end DCA flow. This skill has no scripts of its own — it composes two other skills:

1. **`ripio-login`** — opens an authenticated session.
2. **`ripio-buy`** — places a market buy with the full available fiat balance.

## Flow

1. **Authenticate.** Invoke the `ripio-login` skill and follow its instructions exactly. Handle the interactive branches as documented there:
   - Exit code `3` → ask the user for their TOTP code, run the `--2fa` step.
   - Exit code `4` → ask the user for the magic-link token, run the `--magic-link` step.
   - Exit code `2` → credentials failed. Stop and report.
2. **Buy.** Once login succeeds, invoke the `ripio-buy` skill. It reads `RIPIO_DCA_ASSET` and buys the maximum available balance.
3. **Report** the trade outcome (asset, amount spent, amount received) to the user.

## Configuration

This skill inherits its configuration from the skills it composes:

- `RIPIO_EMAIL`, `RIPIO_PASSWORD` — used by `ripio-login`.
- `RIPIO_DCA_ASSET_ORIGIN`, `RIPIO_DCA_ASSET_TARGET` — used by `ripio-buy`.

If any are missing, the underlying skill will ask.

## Failure Handling

**Do not attempt to fix, work around, or retry failures autonomously.** If
either sub-skill fails at any step, stop immediately and report the following
to the user:

- Which sub-skill failed (`ripio-login` or `ripio-buy`)
- The exact command that was run
- The exit code
- The full stderr/stdout output (untruncated)
- The current page URL and a fresh `openclaw browser snapshot`

If `ripio-login` fails, do **not** invoke `ripio-buy`.

Do not edit any script or SKILL.md. Do not try alternate selectors, alternate
commands, direct browser launches, or other "creative" workarounds. Do not
retry. Do not change the OpenClaw config. The user will investigate and
direct any fix.

## Extending This Skill

- To DCA into multiple assets, invoke `ripio-buy` once per ticker after login.
- To add a minimum-balance threshold, extend `ripio-buy` rather than this orchestrator.
