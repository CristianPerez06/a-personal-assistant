---
name: ripio-buy
description: Places a market buy on Ripio by swapping the maximum available balance of the configured origin currency into the configured target asset. Reads RIPIO_DCA_ASSET_ORIGIN (e.g. ARS) and RIPIO_DCA_ASSET_TARGET (e.g. BTC). Assumes the browser is already logged into Ripio — run the ripio-login skill first, or use the ripio-dca skill for the full login+buy flow. Use when the user explicitly asks to buy alone (after a manual login) or to inspect the buy page.
user-invocable: true
metadata:
  {
    "openclaw":
      { "emoji": "🛒", "requires": { "config": ["browser.enabled"] } },
  }
---

# Ripio Buy

Places a single market buy on Ripio using the **entire available fiat balance** for the asset configured via `RIPIO_DCA_ASSET`.

This skill assumes an authenticated session. If the browser isn't logged in, the script exits with code `4` and you should run the `ripio-login` skill (or the `ripio-dca` orchestrator) first.

## Configuration

Required environment variables:

- **`RIPIO_DCA_ASSET_ORIGIN`** — source currency to spend (e.g. `ARS`).
- **`RIPIO_DCA_ASSET_TARGET`** — ticker of the asset to buy (e.g. `BTC`, `ETH`, `USDT`).

If either is missing, ask the user for the missing value.

## Running the Script

Check both env vars are configured:

```bash
echo "RIPIO_DCA_ASSET_ORIGIN=${RIPIO_DCA_ASSET_ORIGIN:-NOT_SET}"
echo "RIPIO_DCA_ASSET_TARGET=${RIPIO_DCA_ASSET_TARGET:-NOT_SET}"
```

Then run the buy:

```bash
bash /home/node/.openclaw/workspace/skills/ripio-buy/scripts/ripio-buy.sh
```

Exit codes:

- `0` — buy completed successfully.
- `1` — generic / unexpected error (selector not found, page didn't load, etc.).
- `2` — insufficient balance (no fiat available).
- `3` — buy was rejected by Ripio (validation, market closed, etc.).
- `4` — not logged in (run `ripio-login` first).

### Inspection mode

Dump a snapshot of the **current page** without placing any order — useful while iterating on selectors. Run this after `ripio-login` succeeds; the script will verify the URL is on `https://app.ripio.com` before dumping:

```bash
bash /home/node/.openclaw/workspace/skills/ripio-buy/scripts/ripio-buy.sh --inspect
```

## Failure Handling

**Do not attempt to fix, work around, or retry failures autonomously.** If any
script step fails, stop immediately and report the following to the user:

- The exact command that was run
- The exit code
- The full stderr/stdout output (untruncated)
- The current page URL and a fresh `openclaw browser snapshot`

Do not edit the script. Do not try alternate selectors, alternate commands,
direct browser launches, or other "creative" workarounds. Do not retry. Do
not change the OpenClaw config. The user will investigate and direct any fix.

## Post-Trade

After a successful buy, the script prints the trade summary parsed from the confirmation screen. The browser session remains active.
