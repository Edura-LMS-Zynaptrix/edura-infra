#!/usr/bin/env bash
# ==============================================================================
# EDURA Learning Management System — Azure AKS & ACR Provisioning Script
# Issue Reference: DDP-#12
# ==============================================================================
# Prerequisites:
#   - Azure CLI (az) installed and logged in (az login)
#   - kubectl CLI installed
# ==============================================================================

set -euo pipefail

# Configuration Variables
RESOURCE_GROUP="${RESOURCE_GROUP:-edura-rg}"
LOCATION="${LOCATION:-eastasia}"
CLUSTER_NAME="${CLUSTER_NAME:-edura-aks}"
NODE_COUNT="${NODE_COUNT:-2}"
NODE_VM_SIZE="${NODE_VM_SIZE:-Standard_D2s_v5}"
ACR_NAME="${ACR_NAME:-eduracr$RANDOM}" # ACR names must be globally unique

echo "======================================================================"
echo " Starting Azure Infrastructure Provisioning for EDURA"
echo " Resource Group: ${RESOURCE_GROUP}"
echo " Location:       ${LOCATION}"
echo " AKS Cluster:    ${CLUSTER_NAME} (${NODE_COUNT} x ${NODE_VM_SIZE})"
echo " ACR Registry:   ${ACR_NAME}"
echo "======================================================================"

# 1. Create Resource Group
echo "[1/5] Creating Resource Group '${RESOURCE_GROUP}' in '${LOCATION}'..."
az group create --name "${RESOURCE_GROUP}" --location "${LOCATION}" --output table

# 2. Create Azure Container Registry (ACR)
echo "[2/5] Creating Azure Container Registry '${ACR_NAME}'..."
az acr create --resource-group "${RESOURCE_GROUP}" --name "${ACR_NAME}" --sku Standard --output table

# 3. Create Azure Kubernetes Service (AKS) Cluster
echo "[3/5] Creating AKS Cluster '${CLUSTER_NAME}'..."
az aks create \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${CLUSTER_NAME}" \
  --node-count "${NODE_COUNT}" \
  --node-vm-size "${NODE_VM_SIZE}" \
  --generate-ssh-keys \
  --enable-managed-identity \
  --output table

# 4. Attach ACR to AKS Cluster (Grants AcrPull role automatically)
echo "[4/5] Attaching ACR '${ACR_NAME}' to AKS '${CLUSTER_NAME}'..."
az aks update --resource-group "${RESOURCE_GROUP}" --name "${CLUSTER_NAME}" --attach-acr "${ACR_NAME}" --output table

# 5. Fetch Credentials and Verify
echo "[5/5] Fetching kubeconfig and verifying cluster nodes..."
az aks get-credentials --resource-group "${RESOURCE_GROUP}" --name "${CLUSTER_NAME}" --overwrite-existing

echo "----------------------------------------------------------------------"
echo " Node Status:"
kubectl get nodes

echo "======================================================================"
echo " Infrastructure Provisioning Complete!"
echo " ACR Login Server: ${ACR_NAME}.azurecr.io"
echo " Base64 Kubeconfig for GitHub Secrets (KUBE_CONFIG_DATA):"
az aks get-credentials --resource-group "${RESOURCE_GROUP}" --name "${CLUSTER_NAME}" --file - | base64 -w 0
echo ""
echo "======================================================================"
