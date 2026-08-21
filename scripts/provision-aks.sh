#!/bin/bash
# ==============================================================================
# EDURA LMS — Azure AKS & ACR Provisioning Script (DDP-#12)
# ==============================================================================
# Usage:
#   chmod +x scripts/provision-aks.sh
#   ./scripts/provision-aks.sh
# ==============================================================================

set -e

# Configuration variables
RESOURCE_GROUP="${RESOURCE_GROUP:-edura-rg}"
LOCATION="${LOCATION:-eastasia}"
ACR_NAME="${ACR_NAME:-eduracr2026}"
AKS_CLUSTER="${AKS_CLUSTER:-edura-aks}"
NODE_COUNT="${NODE_COUNT:-2}"
NODE_SKU="${NODE_SKU:-Standard_D4s_v3}"

echo "======================================================================"
echo "Starting Azure Infrastructure Provisioning for EDURA LMS"
echo "Resource Group : ${RESOURCE_GROUP}"
echo "Location       : ${LOCATION}"
echo "ACR Registry   : ${ACR_NAME}"
echo "AKS Cluster    : ${AKS_CLUSTER}"
echo "======================================================================"

# Step 1: Create Resource Group
echo "[1/5] Creating Resource Group '${RESOURCE_GROUP}' in ${LOCATION}..."
az group create \
  --name "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --output table

# Step 2: Create Azure Container Registry (ACR)
echo "[2/5] Creating Azure Container Registry '${ACR_NAME}'..."
az acr create \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${ACR_NAME}" \
  --sku Basic \
  --admin-enabled true \
  --output table

# Step 3: Create Azure Kubernetes Service (AKS) cluster
echo "[3/5] Creating AKS cluster '${AKS_CLUSTER}' (Node count: ${NODE_COUNT}, VM Size: ${NODE_SKU})..."
az aks create \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${AKS_CLUSTER}" \
  --node-count "${NODE_COUNT}" \
  --node-vm-size "${NODE_SKU}" \
  --generate-ssh-keys \
  --enable-managed-identity \
  --output table

# Step 4: Attach ACR to AKS Cluster (Grants AcrPull role to AKS)
echo "[4/5] Attaching ACR '${ACR_NAME}' to AKS cluster '${AKS_CLUSTER}'..."
az aks update \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${AKS_CLUSTER}" \
  --attach-acr "${ACR_NAME}" \
  --output table

# Step 5: Get Kubectl Credentials
echo "[5/5] Fetching kubectl credentials for ${AKS_CLUSTER}..."
az aks get-credentials \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${AKS_CLUSTER}" \
  --overwrite-existing

echo "======================================================================"
echo "Provisioning Complete!"
echo "Verify nodes state with: kubectl get nodes"
echo "======================================================================"
