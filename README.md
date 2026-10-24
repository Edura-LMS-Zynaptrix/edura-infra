# EDURA Infra — Docker & Deployment Configurations

This repository manages local development orchestration and cloud deployment configuration for the EDURA Learning Management System.

## Contents
* `nginx/` — Nginx gateway routing configuration
* `postgres/` — Multiple-database initialization script for PostgreSQL container
* `rabbitmq/` — the event bus topology (topic exchange, one queue per consuming service, routing keys): initialization script and tests
* `docker-compose.yml` — Local docker environment orchestrating databases, Redis, RabbitMQ, and the backend services

## How services communicate

**No service calls another service over HTTP.** The browser talks only to the
nginx gateway. Between services there are two mechanisms:

1. **Events.** Whenever a service changes something others care about, it
   publishes an event on one topic exchange, `edura.events`
   (e.g. `course.upserted`, `payment.success`, `access.changed`, `auth.user-registered`).
2. **Local copies.** A service that needs another service's data keeps its own
   small copy in `replica_*` tables, updated from those events. A name lookup,
   an access check or a price check is therefore a query on the service's own
   database, never a network call. Each service still owns its own database.

Delivery is at-least-once and every event sets a row to the state it announces,
so handling one twice is harmless. At startup each service re-announces its
reference data a few seconds after boot, so a new or emptied copy catches up.

The topology below is created by `rabbitmq/setup.py` (the `rabbitmq-setup` init
container); services wait for it before starting. The same queue and
routing-key list lives in `edura-backend/shared/events.py`, which the services
bind from.

| Queue | Read by | Routing keys |
|---|---|---|
| `user.queue` | user_service — creates a profile for each new account, keeps account email/active flag, credits referrals | `auth.user-registered`, `auth.account-updated`, `enrollment.activated` |
| `course.queue` | course_service — the access list, to gate paid lessons | `access.changed` |
| `content.queue` | content_service — the access list, to gate paid media | `access.changed` |
| `enrollment.queue` | enrollment_service — payments (to enroll), plus copies of courses, students and streams | `payment.success`, `subscription.expired`, `course.upserted`, `course.deleted`, `user.profile-upserted`, `user.profile-deleted`, `user.stream-upserted`, `user.stream-deleted` |
| `payment.queue` | payment_service — course prices, to validate free enrollment | `course.upserted`, `course.deleted` |
| `assessment.queue` | assessment_service — access list, courses, students (leaderboards) | `access.changed`, `course.upserted`, `course.deleted`, `user.profile-upserted`, `user.profile-deleted`, `auth.user-registered`, `auth.account-updated` |
| `progress.queue` | progress_service — enrollments, graded attempts, lesson watching | `enrollment.activated`, `assessment.graded`, `lesson.watched` |
| `notification.queue` | notification_service — every email (verification, reset, receipts, reports) | `auth.otp-requested`, `auth.email-verification-requested`, `auth.password-reset-requested`, `auth.password-changed`, `payment.success`, `payment.manual-uploaded`, `assessment.graded`, `certificate.issued`, `proctoring.violation`, `violation.alert`, `report.progress` |
| `admin.queue` | admin_service — names for the chat inbox | `user.profile-upserted`, `user.profile-deleted`, `auth.user-registered`, `auth.account-updated` |
| `analytics.queue` | analytics_service — everything its reports are built from | `auth.user-registered`, `auth.account-updated`, `user.profile-upserted`, `user.profile-deleted`, `course.upserted`, `course.deleted`, `course.module-upserted`, `course.module-deleted`, `access.changed`, `enrollment.changed`, `payment.success`, `payment.receipt-uploaded`, `payment.receipt-reviewed`, `assessment.upserted`, `assessment.deleted`, `assessment.graded`, `badge.awarded` |

Queues from earlier versions that nothing reads any more (`user.referrals.queue`)
are removed by the setup script.

**Data flows (who announces what)**

| Event | Published by | Why others want it |
|---|---|---|
| `auth.user-registered`, `auth.account-updated` | auth_service | user_service builds the profile and keeps email/active flag; others keep names/emails |
| `user.profile-upserted`, `user.profile-deleted`, `user.stream-*` | user_service | names, grade, district, school for leaderboards, pickers and reports |
| `course.upserted`, `course.deleted`, `course.module-*` | course_service | price, owner, title, grade and streams for payment, enrollment, exams and reports |
| `access.changed` | enrollment_service | who may open what, for course, content, assessment and analytics |
| `enrollment.activated`, `enrollment.changed` | enrollment_service | referral credit, progress, enrollment counts |
| `payment.success`, `payment.receipt-*` | payment_service | enrollment, emails, revenue and bank-slip counts |
| `assessment.upserted`, `assessment.deleted`, `assessment.graded`, `badge.awarded` | assessment_service | progress, reports and the admin dashboard |

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

