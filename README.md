# EDURA Infra — Docker & Deployment Configurations

This repository manages local development orchestration and cloud deployment configuration for the EDURA Learning Management System.

## Contents
* `nginx/` — Nginx gateway routing configuration
* `postgres/` — Multiple-database initialization script for PostgreSQL container
* `rabbitmq/` — RabbitMQ topic exchange, queues, and routing key topology initialization script and tests
* `docker-compose.yml` — Local docker environment orchestrating databases, Redis, RabbitMQ, and the backend services
* `scripts/` — Infrastructure provisioning scripts (`provision-aks.sh`)
* `k8s/` — Kubernetes deployment manifests and cluster verification (`hello-world-deployment.yaml`)

## RabbitMQ Topology Architecture
The RabbitMQ setup script (`rabbitmq/setup.py`) is run on startup via the `rabbitmq-setup` init container. It idempotently provisions the topology:
* **Exchange**: `edura.events` (Topic Exchange, durable)
* **Queues**:
  * `notification.queue`
  * `enrollment.queue`
  * `progress.queue`
* **Routing Key Bindings**:
  * `auth.otp-requested` → `notification.queue`
  * `payment.success` → `enrollment.queue`, `notification.queue`
  * `payment.manual-uploaded` → `notification.queue`
  * `enrollment.activated` → `progress.queue`
  * `assessment.graded` → `progress.queue`, `notification.queue`
  * `certificate.issued` → `notification.queue`
  * `lesson.watched` → `progress.queue`

## Local Dev Quickstart
1. Ensure **Docker Desktop** is open and running.
2. In this directory, execute to build backend images:
   ```bash
   docker-compose build
   ```
3. Run the complete stack:
   ```bash
   docker-compose up
   ```
4. Access health checks at `http://localhost/api/auth/health` or `http://localhost/api/users/health`.
5. Access RabbitMQ Management Dashboard at `http://localhost:15672` (using default credentials `guest`/`guest`).

## Azure AKS & ACR Provisioning

To provision the Azure infrastructure (AKS cluster & ACR registry):

1. **Log in to Azure CLI**:
   ```bash
   az login
   ```
2. **Run Provisioning Script**:
   ```bash
   chmod +x scripts/provision-aks.sh
   ./scripts/provision-aks.sh
   ```
   This will:
   - Create Resource Group `edura-rg` in region `eastasia`.
   - Create Azure Container Registry (`eduracr`).
   - Create AKS Cluster `edura-aks` with 2 nodes (`Standard_D2s_v5`).
   - Grant `AcrPull` permission to AKS automatically using `--attach-acr`.

3. **Verify Cluster Access**:
   ```bash
   az aks get-credentials --resource-group edura-rg --name edura-aks
   kubectl get nodes
   ```

4. **Verify Deployment (hello-world)**:
   ```bash
   kubectl apply -f k8s/hello-world-deployment.yaml
   kubectl get pods -w
   ```

## CI/CD Deployment & GitHub Secrets Configuration

The GitHub Actions CI/CD pipeline defined in `.github/workflows/ci.yml` builds, tests, and deploys the EDURA Learning Management System. 

To enable staging and production deployment stages, you must configure the following **Secrets** in your GitHub repository:

### Required GitHub Secrets for AKS/ACR Deployment
* `AZURE_CLIENT_ID` — Azure service principal or workload identity client ID
* `AZURE_TENANT_ID` — Azure Active Directory tenant ID
* `ACR_LOGIN_SERVER` — URL of ACR (e.g. `eduracr.azurecr.io`)
* `AKS_CLUSTER_NAME` — `edura-aks`
* `AKS_RESOURCE_GROUP` — `edura-rg`
* `KUBE_CONFIG_DATA` — Base64-encoded `kubeconfig` string from `az aks get-credentials`

### 1. Adding GitHub Secrets
To add secrets to your repository:
1. Go to your repository on GitHub: `https://github.com/<org-or-username>/edura-infra`.
2. Navigate to **Settings** -> **Secrets and variables** -> **Actions**.
3. Click the **New repository secret** button.
4. Add the required keys (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `ACR_LOGIN_SERVER`, `AKS_CLUSTER_NAME`, `AKS_RESOURCE_GROUP`, `KUBE_CONFIG_DATA`) and paste their values.

### 2. Manual Production Approval Gate
The production deployment stage (`deploy-prod`) uses a GitHub Environment called `production`.
To set up the manual approval gate:
1. Go to **Settings** -> **Environments**.
2. Click **New environment** and name it `production`.
3. Check the **Required reviewers** box under *Deployment protection rules*.
4. Select the reviewers who must approve production deployments before they execute.
