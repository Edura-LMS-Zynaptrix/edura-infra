# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- AKS build-push-deploy pipeline for staging, with OIDC login to Azure and health checks after deployment (`deploy.yml`, `scripts/`)
- Security response headers on the public edge: HSTS, X-Content-Type-Options, X-Frame-Options and Referrer-Policy (DDP-#64)
- Lint and security-scan stages for the infra pipeline (`quality.yml`) (DDP-#56)
- Gateway and edge configuration tests, now run in CI as `Gateway & Edge Config Tests` (DDP-#72)
- Readiness, liveness and startup probes for every backend Deployment, and a second `course-service` replica (DDP-#73)
- Infra CI also runs on `feature/**`, `fix/**`, `hotfix/**` and `release/**` branches
- README: badges, deployed links, prerequisites, run steps and RabbitMQ communication details

### Changed
- RabbitMQ: the default `guest` account is replaced by an `edura` account whose password comes from the `rabbitmq-credentials` secret; the deploy script creates the account and deletes `guest` after the rollouts (DDP-#73)
- Gateway test for the enrollment route corrected (the enrollment service is a pass-through route)

### Fixed
- Deployment: service-link environment variables disabled, gateway rate limit corrected, deploy scripts made executable on CI runners, Azure scopes no longer rewritten by Git Bash in `setup-github-oidc.sh`

## [0.3.0] - 2026-10-15

### Added
- Azure Kubernetes Service cluster, container registry and a hello-world pod verification (provisioning script)
- Nginx upstream blocks and location routing for all 11 services
- RabbitMQ exchanges, queues and routing keys for inter-service events, with a script verification job and a Docker Compose smoke test in CI

### Changed
- Nginx CORS headers updated and `client_max_body_size` raised for uploads
- CI split into separate backend and frontend stages; dependency-audit advisories reported without failing the infra build; Node version flag added

### Fixed
- Nginx routing rule for the enrollment service
- CI repository paths, missing environment file and RabbitMQ setup path errors

## [0.2.0] - 2026-08-04

### Added
- GitHub Actions CI pipeline with lint, build, unit-test and security stages

### Changed
- README updated

### Fixed
- Docker build context, backend test isolation by service directory, per-service PostgreSQL databases in the test loop, `pip install` and `pip-audit` workflow syntax

## [0.1.0] - 2026-06-23

### Added
- Infrastructure environment configuration and the first CI pipeline scaffold

### Changed
- Local PostgreSQL container replaced by Neon

[Unreleased]: https://github.com/Edura-LMS-Zynaptrix/edura-infra/compare/v0.3.0...develop
[0.3.0]: https://github.com/Edura-LMS-Zynaptrix/edura-infra/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/Edura-LMS-Zynaptrix/edura-infra/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Edura-LMS-Zynaptrix/edura-infra/releases/tag/v0.1.0
