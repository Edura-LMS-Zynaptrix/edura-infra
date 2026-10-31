#!/bin/bash
# ==============================================================================
# EDURA LMS — Upload the 11 service .env files as GitHub environment secrets
# ==============================================================================
# The deploy pipeline reads AUTH_SERVICE_ENV, USER_SERVICE_ENV, ... from the
# GitHub environment it deploys to, and turns each into a Kubernetes Secret.
#
#   ./scripts/sync-github-secrets.sh staging                      # from ../edura-backend/*/.env
#   ENV_SOURCE=../prod-env ./scripts/sync-github-secrets.sh production   # from ../prod-env/auth.env, ...
#
# Re-run it whenever a value changes, then redeploy. Needs gh (org admin).
# ==============================================================================

set -euo pipefail

# Git Bash opened before GitHub CLI was installed doesn't have it on PATH yet.
command -v gh >/dev/null 2>&1 || export PATH="$PATH:/c/Program Files/GitHub CLI"
command -v gh >/dev/null 2>&1 || { echo "GitHub CLI (gh) not found. Install it (winget install GitHub.cli), then reopen VS Code."; exit 1; }

ENVIRONMENT="${1:?Usage: sync-github-secrets.sh staging|production}"
GITHUB_ORG="${GITHUB_ORG:-Edura-LMS-Zynaptrix}"
GITHUB_REPO="${GITHUB_REPO:-edura-infra}"
ENV_SOURCE="${ENV_SOURCE:-}"
SERVICES="auth user course content enrollment payment assessment progress notification analytics admin"

for s in $SERVICES; do
  if [ -n "$ENV_SOURCE" ]; then src="${ENV_SOURCE}/${s}.env"; else src="../edura-backend/${s}_service/.env"; fi
  [ -s "$src" ] || { echo "Missing or empty ${src}"; exit 1; }
  name="$(echo "$s" | tr '[:lower:]' '[:upper:]')_SERVICE_ENV"
  tr -d '\r' < "$src" | gh secret set "$name" --repo "${GITHUB_ORG}/${GITHUB_REPO}" --env "$ENVIRONMENT"
  echo "  ${ENVIRONMENT}: ${name} <- ${src}"
done
