# EDURA Infra — Docker & Deployment Configurations

This repository manages local development orchestration and cloud deployment configuration for the EDURA Learning Management System.

## Contents
* `nginx/` — Nginx gateway routing configuration
* `postgres/` — Multiple-database initialization script for PostgreSQL container
* `rabbitmq/` — RabbitMQ topic exchange, queues, and routing key topology initialization script and tests
* `docker-compose.yml` — Local docker environment orchestrating databases, Redis, RabbitMQ, and the backend services

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

## Azure AKS Cluster & ACR Registry Provisioning (DDP-#12)

The `scripts/provision-aks.sh` script automates the creation and configuration of the Azure AKS Kubernetes cluster and Azure Container Registry (ACR).

### 1. Provisioning Azure Infrastructure
Run the provisioning script from the repository root:
```bash
chmod +x scripts/provision-aks.sh
./scripts/provision-aks.sh
```

This script will:
* Create Resource Group: `edura-rg` (Region: `eastasia`)
* Create Azure Container Registry (ACR): `eduracr2026`
* Create AKS Cluster: `edura-aks` (2 × `Standard_D4s_v3` nodes)
* Link ACR to AKS via `az aks update --attach-acr eduracr2026` to grant image pull permissions without secret management
* Configure `kubectl` context to connect to `edura-aks`

### 2. Verification with Hello-World Pod
Verify cluster connectivity and pod execution:
```bash
# 1. Verify node readiness
kubectl get nodes

# 2. Deploy test pod
kubectl apply -f k8s/hello-world.yaml

# 3. Verify pod running status
kubectl get pods -l app=hello-world
kubectl logs -l app=hello-world

# 4. Clean up test deployment
kubectl delete -f k8s/hello-world.yaml
```

### 3. Required GitHub Secrets for Azure Deployment
In GitHub Repository **Settings** -> **Secrets and variables** -> **Actions**, configure:
* `AZURE_CLIENT_ID`: Service principal / app registration client ID
* `AZURE_TENANT_ID`: Azure Active Directory tenant ID
* `ACR_LOGIN_SERVER`: `eduracr2026.azurecr.io`
* `AKS_CLUSTER_NAME`: `edura-aks`
* `AKS_RESOURCE_GROUP`: `edura-rg`

