#!/bin/bash
# ==============================================================================
# EDURA LMS — Deploy already-pushed images to one AKS environment (DDP-#18)
# ==============================================================================
# Used by .github/workflows/deploy.yml, and by scripts/deploy-aks.sh for manual
# deploys. kubectl must already point at the cluster.
#
#   ./scripts/deploy-env.sh staging|production
#
# Required environment variables:
#   ACR_LOGIN_SERVER  e.g. eduracrzyn.azurecr.io
#   IMAGE_TAG         tag of the 11 backend images (the edura-backend git SHA)
#   SETUP_TAG         tag of the rabbitmq-setup image (the edura-infra git SHA)
#   FRONTEND_IMAGE    full frontend image reference (built per environment)
#   SECRETS_DIR       folder holding auth.env, user.env, ... admin.env
# ==============================================================================

set -euo pipefail

ENVIRONMENT="${1:?Usage: deploy-env.sh staging|production}"
ENV_DIR="k8s/${ENVIRONMENT}"
[ -f "${ENV_DIR}/env" ] || { echo "Unknown environment '${ENVIRONMENT}' (no ${ENV_DIR}/env)"; exit 1; }
# shellcheck source=/dev/null
source "${ENV_DIR}/env"

: "${ACR_LOGIN_SERVER:?}" "${IMAGE_TAG:?}" "${SETUP_TAG:?}" "${FRONTEND_IMAGE:?}" "${SECRETS_DIR:?}"
PUBLIC_URL="https://${DOMAIN}"
DEPLOY_ID="${DEPLOY_ID:-$(date +%Y%m%d%H%M%S)}"
SERVICES="auth user course content enrollment payment assessment progress notification analytics admin"
NS=(-n "$NAMESPACE")

# Relative scratch folder: Git Bash on Windows mangles /tmp paths for kubectl.
TMP_DIR=".deploy-tmp/${ENVIRONMENT}"
mkdir -p "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

render() {
  sed -e "s|__ACR__|${ACR_LOGIN_SERVER}|g" \
      -e "s|__TAG__|${IMAGE_TAG}|g" \
      -e "s|__SETUP_TAG__|${SETUP_TAG}|g" \
      -e "s|__FRONTEND_IMAGE__|${FRONTEND_IMAGE}|g" \
      -e "s|__DEPLOY_ID__|${DEPLOY_ID}|g" \
      -e "s|__DOMAIN__|${DOMAIN}|g" \
      -e "s|__PIP_NAME__|${PUBLIC_IP_NAME}|g" "$1"
}

echo "== Deploying to ${ENVIRONMENT} (${NAMESPACE}) → ${PUBLIC_URL}"
echo "   backend=${IMAGE_TAG}  setup=${SETUP_TAG}  frontend=${FRONTEND_IMAGE##*/}"

echo "[1/5] Namespace, secrets and gateway config..."
kubectl apply -f "${ENV_DIR}/namespace.yaml"
for s in $SERVICES; do
  src="${SECRETS_DIR}/${s}.env"
  [ -s "$src" ] || { echo "Missing or empty ${src}"; exit 1; }
  # FRONTEND_URL always matches the environment's public URL (emails, redirects).
  grep -v '^FRONTEND_URL=' "$src" | tr -d '\r' > "${TMP_DIR}/${s}.env"
  echo "FRONTEND_URL=${PUBLIC_URL}" >> "${TMP_DIR}/${s}.env"
  kubectl "${NS[@]}" create secret generic "${s}-service-env" \
    --from-env-file="${TMP_DIR}/${s}.env" --dry-run=client -o yaml | kubectl apply -f -
done
sed "s|__PUBLIC_URL__|${PUBLIC_URL}|g" k8s/base/nginx.conf > "${TMP_DIR}/nginx.conf"
kubectl "${NS[@]}" create configmap gateway-nginx-conf \
  --from-file=nginx.conf="${TMP_DIR}/nginx.conf" --dry-run=client -o yaml | kubectl apply -f -

echo "[2/5] Redis and RabbitMQ..."
render k8s/base/10-redis.yaml | kubectl "${NS[@]}" apply -f -
# A finished Job is immutable; recreate it so the topology is re-applied each deploy.
kubectl "${NS[@]}" delete job rabbitmq-setup --ignore-not-found
render k8s/base/11-rabbitmq.yaml | kubectl "${NS[@]}" apply -f -
kubectl "${NS[@]}" rollout status statefulset/rabbitmq --timeout=300s
kubectl "${NS[@]}" wait --for=condition=complete job/rabbitmq-setup --timeout=300s

echo "[3/5] Services, frontend, gateway, HTTPS edge..."
for f in 20-backend.yaml 30-frontend.yaml 40-gateway.yaml 50-edge.yaml; do
  render "k8s/base/${f}" | kubectl "${NS[@]}" apply -f -
done

echo "[4/5] Waiting for rollouts..."
for d in $(kubectl "${NS[@]}" get deployments -o name); do
  kubectl "${NS[@]}" rollout status "$d" --timeout=300s
done

echo "[5/5] Pods:"
kubectl "${NS[@]}" get pods -o wide
echo "== ${ENVIRONMENT} deployed: ${PUBLIC_URL}"
