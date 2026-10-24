#!/bin/bash
# ==============================================================================
# EDURA LMS — Azure AKS & ACR Provisioning Script (DDP-#12)
# ==============================================================================
# Usage:
#   chmod +x scripts/provision-aks.sh
#   ACR_NAME=<globally-unique-name> ./scripts/provision-aks.sh
#
# Defaults are the minimum that runs EDURA (ADR-13): eastus, next to the Neon
# databases in AWS us-east-1; ONE Standard_D2als_v7 node (2 vCPU / 4 GB) with a
# 30 GB OS disk; a static IP for staging only. Roughly US$95/month.
# (Free-trial subscriptions may not use B-series sizes for AKS; D2als_v7 is the
# cheapest 2-vCPU size they allow. 8 GB alternative: NODE_SKU=Standard_D2as_v7, +~US$7.)
# Scale up later without code changes, e.g.:
#   NODE_SKU=Standard_D2s_v3 NODE_COUNT=2 PUBLIC_IP_ENVS="staging production" ./scripts/provision-aks.sh
# ==============================================================================

set -e

# Git Bash opened before Azure CLI was installed doesn't have it on PATH yet.
command -v az >/dev/null 2>&1 || export PATH="$PATH:/c/Program Files/Microsoft SDKs/Azure/CLI2/wbin"
command -v az >/dev/null 2>&1 || { echo "Azure CLI (az) not found. Install it, then reopen VS Code."; exit 1; }

# Configuration variables
RESOURCE_GROUP="${RESOURCE_GROUP:-edura-rg}"
LOCATION="${LOCATION:-eastus}"
ACR_NAME="${ACR_NAME:-eduracrzynaptrix}"
AKS_CLUSTER="${AKS_CLUSTER:-edura-aks}"
NODE_COUNT="${NODE_COUNT:-1}"
NODE_SKU="${NODE_SKU:-Standard_D2als_v7}"
# 30 GB managed OS disk instead of the 128 GB default (a much cheaper disk tier).
OS_DISK_GB="${OS_DISK_GB:-30}"
# Environments that get a static public IP (each IP is ~US$3.6/month).
PUBLIC_IP_ENVS="${PUBLIC_IP_ENVS:-staging}"

echo "======================================================================"
echo "Starting Azure Infrastructure Provisioning for EDURA LMS"
echo "Resource Group : ${RESOURCE_GROUP}"
echo "Location       : ${LOCATION}"
echo "ACR Registry   : ${ACR_NAME}"
echo "AKS Cluster    : ${AKS_CLUSTER} (${NODE_COUNT} x ${NODE_SKU})"
echo "======================================================================"

# Step 1: Create Resource Group
echo "[1/6] Creating Resource Group '${RESOURCE_GROUP}' in ${LOCATION}..."
az group create \
  --name "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --output table

# Step 2: Create Azure Container Registry (ACR)
echo "[2/6] Creating Azure Container Registry '${ACR_NAME}'..."
az acr create \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${ACR_NAME}" \
  --sku Basic \
  --output table

# Step 3: Create Azure Kubernetes Service (AKS) cluster
echo "[3/6] Creating AKS cluster '${AKS_CLUSTER}' (Node count: ${NODE_COUNT}, VM Size: ${NODE_SKU})..."
az aks create \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${AKS_CLUSTER}" \
  --tier free \
  --node-count "${NODE_COUNT}" \
  --node-vm-size "${NODE_SKU}" \
  --node-osdisk-size "${OS_DISK_GB}" \
  --node-osdisk-type Managed \
  --generate-ssh-keys \
  --enable-managed-identity \
  --output table

# Step 4: Attach ACR to AKS Cluster (Grants AcrPull role to the cluster's managed identity)
echo "[4/6] Attaching ACR '${ACR_NAME}' to AKS cluster '${AKS_CLUSTER}'..."
az aks update \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${AKS_CLUSTER}" \
  --attach-acr "${ACR_NAME}" \
  --output table

# Step 5: Get Kubectl Credentials
echo "[5/6] Fetching kubectl credentials for ${AKS_CLUSTER}..."
az aks get-credentials \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${AKS_CLUSTER}" \
  --overwrite-existing

# Step 6: Static public IPs for the HTTPS edge of each environment.
# They live in the node resource group so the cluster can attach them to its
# load balancer; DNS A records point at them and never need to change.
NODE_RG="$(az aks show --resource-group "${RESOURCE_GROUP}" --name "${AKS_CLUSTER}" --query nodeResourceGroup -o tsv | tr -d '\r')"
echo "[6/6] Creating static public IPs in ${NODE_RG}..."
for env in ${PUBLIC_IP_ENVS}; do
  az network public-ip create \
    --resource-group "${NODE_RG}" \
    --name "edura-${env}-ip" \
    --sku Standard \
    --allocation-method Static \
    --output none
  echo "  edura-${env}-ip = $(az network public-ip show --resource-group "${NODE_RG}" --name "edura-${env}-ip" --query ipAddress -o tsv | tr -d '\r')"
done

echo "======================================================================"
echo "Provisioning Complete!"
echo "Verify nodes state with: kubectl get nodes"
echo "Point the DNS A record(s) at the IP(s) above (docs/AZURE-DEPLOYMENT.md, step 5)."
echo "======================================================================"
