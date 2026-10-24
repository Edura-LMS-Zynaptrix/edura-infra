#!/bin/bash
# ==============================================================================
# EDURA LMS — Let GitHub Actions deploy to Azure without stored passwords (DDP-#12 AC4)
# ==============================================================================
# Creates an Entra ID app registration that edura-infra's workflows sign in as
# via OpenID Connect (federated credentials), grants it Contributor on the
# resource group only (push to ACR + deploy to AKS), and stores the
# non-secret IDs as GitHub Actions secrets on edura-infra.
#
#   GITHUB_ORG=Edura-LMS-Zynaptrix ./scripts/setup-github-oidc.sh
#
# Needs: az (logged in), gh (logged in as an org admin). Safe to re-run.
# ==============================================================================

set -euo pipefail

# Git Bash opened before Azure CLI was installed doesn't have it on PATH yet.
command -v az >/dev/null 2>&1 || export PATH="$PATH:/c/Program Files/Microsoft SDKs/Azure/CLI2/wbin"
command -v az >/dev/null 2>&1 || { echo "Azure CLI (az) not found. Install it, then reopen VS Code."; exit 1; }

# Same for the GitHub CLI.
command -v gh >/dev/null 2>&1 || export PATH="$PATH:/c/Program Files/GitHub CLI"
command -v gh >/dev/null 2>&1 || { echo "GitHub CLI (gh) not found. Install it (winget install GitHub.cli), then reopen VS Code."; exit 1; }

GITHUB_ORG="${GITHUB_ORG:-Edura-LMS-Zynaptrix}"
GITHUB_REPO="${GITHUB_REPO:-edura-infra}"
RESOURCE_GROUP="${RESOURCE_GROUP:-edura-rg}"
AKS_CLUSTER="${AKS_CLUSTER:-edura-aks}"
ACR_NAME="${ACR_NAME:-eduracrzynaptrix}"
APP_NAME="${APP_NAME:-edura-github-deploy}"

# Git Bash rewrites arguments that start with "/" into Windows paths, which turns
# Azure scopes like /subscriptions/... into C:/Program Files/Git/subscriptions/...
export MSYS_NO_PATHCONV=1

clean() { tr -d '\r'; }

SUBSCRIPTION_ID="$(az account show --query id -o tsv | clean)"
TENANT_ID="$(az account show --query tenantId -o tsv | clean)"
RG_ID="$(az group show --name "$RESOURCE_GROUP" --query id -o tsv | clean)"
ACR_LOGIN_SERVER="$(az acr show --name "$ACR_NAME" --query loginServer -o tsv | clean)"

echo "[1/4] App registration '${APP_NAME}'..."
APP_ID="$(az ad app list --display-name "$APP_NAME" --query '[0].appId' -o tsv | clean)"
if [ -z "$APP_ID" ]; then
  APP_ID="$(az ad app create --display-name "$APP_NAME" --query appId -o tsv | clean)"
fi
az ad sp show --id "$APP_ID" >/dev/null 2>&1 || az ad sp create --id "$APP_ID" --output none

echo "[2/4] Granting Contributor on ${RESOURCE_GROUP}..."
# Role assignments can take a few seconds to see a brand-new service principal.
assigned=""
for _ in 1 2 3 4 5; do
  if az role assignment create --assignee "$APP_ID" --role Contributor --scope "$RG_ID" --output none; then
    assigned=1
    break
  fi
  sleep 10
done
[ -n "$assigned" ] || { echo "Could not grant Contributor on ${RG_ID}"; exit 1; }

echo "[3/4] Federated credentials (which workflow runs may sign in)..."
add_cred() {
  local name="$1" subject="$2"
  if az ad app federated-credential show --id "$APP_ID" --federated-credential-id "$name" >/dev/null 2>&1; then
    echo "  = ${name}"
    return
  fi
  az ad app federated-credential create --id "$APP_ID" --output none --parameters "{
    \"name\": \"${name}\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"${subject}\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }"
  echo "  + ${name} -> ${subject}"
}
# Image builds run on the branch; deploy jobs run in a GitHub environment.
add_cred "edura-infra-develop"     "repo:${GITHUB_ORG}/${GITHUB_REPO}:ref:refs/heads/develop"
add_cred "edura-infra-main"        "repo:${GITHUB_ORG}/${GITHUB_REPO}:ref:refs/heads/main"
add_cred "edura-infra-staging"     "repo:${GITHUB_ORG}/${GITHUB_REPO}:environment:staging"
add_cred "edura-infra-production"  "repo:${GITHUB_ORG}/${GITHUB_REPO}:environment:production"

echo "[4/4] Writing GitHub Actions secrets on ${GITHUB_ORG}/${GITHUB_REPO}..."
R=(--repo "${GITHUB_ORG}/${GITHUB_REPO}")
gh secret set AZURE_CLIENT_ID       "${R[@]}" --body "$APP_ID"
gh secret set AZURE_TENANT_ID       "${R[@]}" --body "$TENANT_ID"
gh secret set AZURE_SUBSCRIPTION_ID "${R[@]}" --body "$SUBSCRIPTION_ID"
gh secret set ACR_LOGIN_SERVER      "${R[@]}" --body "$ACR_LOGIN_SERVER"
gh secret set AKS_CLUSTER_NAME      "${R[@]}" --body "$AKS_CLUSTER"
gh secret set AKS_RESOURCE_GROUP    "${R[@]}" --body "$RESOURCE_GROUP"

echo "Done. Client ID: ${APP_ID}"
