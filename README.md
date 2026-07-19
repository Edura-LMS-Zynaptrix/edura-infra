# EDURA Infra — Docker & Deployment Configurations

This repository manages local development orchestration and cloud deployment configuration for the EDURA Learning Management System.

## Contents
* `nginx/` — Nginx gateway routing configuration
* `postgres/` — Multiple-database initialization script for PostgreSQL container
* `docker-compose.yml` — Local docker environment orchestrating databases, Redis, RabbitMQ, and the backend services

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

## CI/CD Deployment & GitHub Secrets Configuration

The GitHub Actions CI/CD pipeline defined in `.github/workflows/ci.yml` builds, tests, and deploys the EDURA Learning Management System. 

To enable staging and production deployment stages, you must configure the following **Secrets** in your GitHub repository:

### 1. Adding GitHub Secrets
To add secrets to your repository:
1. Go to your repository on GitHub: `https://github.com/<org-or-username>/edura-infra`.
2. Navigate to **Settings** -> **Secrets and variables** -> **Actions**.
3. Click the **New repository secret** button.
4. Add the required keys (e.g. `STAGING_DEPLOY_TOKEN`, `PROD_DEPLOY_TOKEN`, or registry credentials) and paste their values.

### 2. Manual Production Approval Gate
The production deployment stage (`deploy-prod`) uses a GitHub Environment called `production`.
To set up the manual approval gate:
1. Go to **Settings** -> **Environments**.
2. Click **New environment** and name it `production`.
3. Check the **Required reviewers** box under *Deployment protection rules*.
4. Select the reviewers who must approve production deployments before they execute.

