# Self-contained image for the a-personal-assistant.
#
# Bakes in everything needed to run the ripio-* skills with no manual setup:
#   - System libs for headless Chromium
#   - Playwright Chromium binary
#   - All three skills (ripio-login, ripio-buy, ripio-dca)
#   - An entrypoint that pins openclaw browser config from the bundled
#     Chromium and syncs skills into the workspace volume on every start
#
# Base image: pinned upstream OpenClaw image from GHCR. Pinned to a specific
# version (rather than :latest) so rebuilds are deterministic and we don't
# get surprised by upstream changes. Bump this tag when intentionally
# upgrading OpenClaw.
FROM ghcr.io/openclaw/openclaw:2026.4.27

USER root

# 1. System libs for headless Chromium.
RUN apt-get update && apt-get install -y --no-install-recommends \
      libnspr4 libnss3 libatk1.0-0 libatk-bridge2.0-0 \
      libdbus-1-3 libcups2 libxkbcommon0 libatspi2.0-0 \
      libxcomposite1 libxdamage1 libxfixes3 libxrandr2 \
      libgbm1 libasound2 libcairo2 libpango-1.0-0 dbus \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/dbus

USER node

# 2. Bundled Chromium via Playwright (~150 MB; lands in
#    /home/node/.cache/ms-playwright/chromium-XXXX/chrome-linux/chrome).
RUN node /app/node_modules/playwright-core/cli.js install chromium

# 3. Skills bundled at /opt/a-personal-assistant/skills (a non-mount path) so the
#    workspace volume can't hide them at runtime. The entrypoint copies
#    them into /home/node/.openclaw/workspace/skills on every startup,
#    so updating the image automatically deploys updated skills.
COPY --chown=node:node skills/ /opt/a-personal-assistant/skills/

# 4. Entrypoint pins browser.* config and syncs skills (with a chown to
#    fix workspace volume ownership if Docker initialized it as root),
#    then drops privileges to node and chains to CMD.
USER root
COPY a-personal-assistant-entrypoint.sh /usr/local/bin/a-personal-assistant-entrypoint.sh
RUN chmod +x /usr/local/bin/a-personal-assistant-entrypoint.sh

# Entrypoint runs as root so it can chown the workspace volume if Docker
# initialized it with the wrong ownership. It then `runuser`s the gateway
# as node before exec.
ENTRYPOINT ["/usr/local/bin/a-personal-assistant-entrypoint.sh"]
CMD ["node", "dist/index.js", "gateway", "--bind", "lan", "--port", "18789"]
