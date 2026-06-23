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
