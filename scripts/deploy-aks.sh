#!/bin/bash
# ==============================================================================
# EDURA LMS — Manual build + deploy from your PC (fallback for the pipeline)
# ==============================================================================
# The normal path is GitHub Actions (.github/workflows/deploy.yml). Use this
# for the very first deploy, or when the pipeline is down before a demo.
#
#   ACR_NAME=<your-acr> ./scripts/deploy-aks.sh staging|production
#
# Builds from the local ../edura-backend and ../edura-frontend checkouts (tagged
# with their current git SHA, like the pipeline does) and uses their local
# .env files as secrets. Run `az aks get-credentials` first (provision-aks.sh does).
# ==============================================================================

set -euo pipefail

# Git Bash opened before Azure CLI was installed doesn't have it on PATH yet.
command -v az >/dev/null 2>&1 || export PATH="$PATH:/c/Program Files/Microsoft SDKs/Azure/CLI2/wbin"
command -v az >/dev/null 2>&1 || { echo "Azure CLI (az) not found. Install it, then reopen VS Code."; exit 1; }

ENVIRONMENT="${1:?Usage: ACR_NAME=<acr> ./scripts/deploy-aks.sh staging|production}"
RESOURCE_GROUP="${RESOURCE_GROUP:-edura-rg}"
ACR_NAME="${ACR_NAME:?Set ACR_NAME to the registry created by provision-aks.sh}"
BACKEND_DIR="../edura-backend"
FRONTEND_DIR="../edura-frontend"
SERVICES="auth user course content enrollment payment assessment progress notification analytics admin"
# shellcheck source=/dev/null
source "k8s/${ENVIRONMENT}/env"

sha() { git -C "$1" rev-parse HEAD; }
dirty() { [ -n "$(git -C "$1" status --porcelain)" ] && echo "-dirty" || true; }

az acr login --name "$ACR_NAME"
export ACR_LOGIN_SERVER
ACR_LOGIN_SERVER="$(az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query loginServer -o tsv | tr -d '\r')"
IMAGE_TAG="$(sha "$BACKEND_DIR")$(dirty "$BACKEND_DIR")"; export IMAGE_TAG
SETUP_TAG="$(sha .)$(dirty .)"; export SETUP_TAG
FRONTEND_TAG="$(sha "$FRONTEND_DIR")$(dirty "$FRONTEND_DIR")-${ENVIRONMENT}"
export FRONTEND_IMAGE="${ACR_LOGIN_SERVER}/edura-frontend:${FRONTEND_TAG}"

echo "Building images (backend ${IMAGE_TAG})..."
for s in $SERVICES; do
  img="${ACR_LOGIN_SERVER}/edura-${s}-service:${IMAGE_TAG}"
  echo "  -> ${img}"
  docker build --platform linux/amd64 -q -t "$img" -f "${BACKEND_DIR}/${s}_service/Dockerfile" "$BACKEND_DIR"
  docker push -q "$img"
done
docker build --platform linux/amd64 -q -t "${ACR_LOGIN_SERVER}/edura-rabbitmq-setup:${SETUP_TAG}" ./rabbitmq
docker push -q "${ACR_LOGIN_SERVER}/edura-rabbitmq-setup:${SETUP_TAG}"

GOOGLE_CLIENT_ID="$(grep -E '^NEXT_PUBLIC_GOOGLE_CLIENT_ID=' "${FRONTEND_DIR}/.env" 2>/dev/null | cut -d= -f2- | tr -d '\r' || true)"
docker build --platform linux/amd64 -q -t "$FRONTEND_IMAGE" \
  --build-arg NEXT_PUBLIC_API_URL="https://${DOMAIN}" \
  --build-arg NEXT_PUBLIC_GOOGLE_CLIENT_ID="$GOOGLE_CLIENT_ID" \
  "$FRONTEND_DIR"
docker push -q "$FRONTEND_IMAGE"

# Local .env files → the layout deploy-env.sh expects.
export SECRETS_DIR=".deploy-tmp/local-secrets"
mkdir -p "$SECRETS_DIR"
trap 'rm -rf .deploy-tmp' EXIT
for s in $SERVICES; do cp "${BACKEND_DIR}/${s}_service/.env" "${SECRETS_DIR}/${s}.env"; done

bash ./scripts/deploy-env.sh "$ENVIRONMENT"
