# EDURA Infra — Docker & Deployment Configurations

This repository manages local development orchestration for the EDURA Learning Management System.

> **Requires** the `edura-backend` repo cloned in the same parent folder as this repo.

---

## Contents

- `docker-compose.yml` — Orchestrates all services, databases, and the API gateway
- `nginx/nginx.conf` — Nginx reverse proxy routing config
- `postgres/init-dbs.sh` — Init script that creates one database per service on first boot
- `.env.example` — Template for required environment variables

---

## Setup

**1. Clone both repos side by side**

```bash
git clone https://github.com/Edura-LMS-Zynaptrix/edura-infra.git
git clone https://github.com/Edura-LMS-Zynaptrix/edura-backend.git
```

**2. Create your `.env` file**

```bash
cp .env.example .env
```

Update `SECRET_KEY` to a strong random value before any non-local use.

**3. Build and start everything**

```bash
docker compose up --build
```

On first boot, PostgreSQL will automatically create all service databases using `postgres/init-dbs.sh`. Services wait for all datastores to be healthy before starting.

---

## Services

All services are accessible via Nginx on port `80`, or directly on their own port.

| Service | Port | Nginx Path | Database |
|---|---|---|---|
| auth_service | 8001 | `/api/auth/` | auth_db |
| user_service | 8002 | `/api/users/` | user_db |
| course_service | 8003 | `/api/courses/` | course_db |
| content_service | 8004 | `/api/content/` | content_db |
| enrollment_service | 8005 | `/api/enrollments/` | enrollment_db |
| payment_service | 8006 | `/api/payments/` | payment_db |
| assessment_service | 8007 | `/api/assessments/` | assessment_db |
| progress_service | 8008 | `/api/progress/` | progress_db |
| notification_service | 8009 | `/api/notifications/` | notification_db |
| analytics_service | 8010 | `/api/analytics/` | analytics_db |
| admin_service | 8011 | `/api/admin/` | admin_db |

**Infrastructure:**

| Service | Port | Notes |
|---|---|---|
| postgres | 5432 | Shared PostgreSQL instance, one DB per service |
| redis | 6379 | Cache and session store |
| rabbitmq | 5672 / 15672 | Message broker (management UI on 15672) |
| nginx | 80 | API gateway |

RabbitMQ management UI: `http://localhost:15672` — credentials: `guest` / `guest`

---

## Environment Variables

The root `.env` file is used by `docker-compose.yml` for datastore credentials.
Each service also has its own `.env` file at `edura-backend/<service_name>/.env`.

**Root `.env` variables:**

| Variable | Description |
|---|---|
| `POSTGRES_USER` | PostgreSQL superuser name |
| `POSTGRES_PASSWORD` | PostgreSQL password (**required**) |
| `POSTGRES_DB` | Default admin database |
| `REDIS_HOST` | Redis hostname |
| `REDIS_PORT` | Redis port |
| `RABBITMQ_USER` | RabbitMQ username |
| `RABBITMQ_PASS` | RabbitMQ password |
| `SECRET_KEY` | JWT / app secret key |

---

## Useful Commands

```bash
# Build and start all services
docker compose up --build

# Start in background
docker compose up -d

# Stop all services
docker compose down

# Stop and wipe all data volumes (resets all databases)
docker compose down -v

# Logs for a specific service
docker compose logs -f auth_service

# Restart a single service
docker compose restart auth_service

# Check container status
docker compose ps
```

---

## Hot Reload

Each service mounts its own source directory as a volume, so code changes reflect inside the container without rebuilding. If you add new packages to `requirements.txt`, rebuild that service:

```bash
docker compose up --build auth_service
```
