FROM alpine/openclaw:latest

# Copy custom skills into the workspace
COPY --chown=node:node skills/ /home/node/.openclaw/workspace/skills/
