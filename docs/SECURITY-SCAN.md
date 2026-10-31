# Security scan and accepted vulnerabilities

The **Security Scan** job in `.github/workflows/quality.yml` implements the
dependency vulnerability scan required by development guideline section 7.2. It runs on
every pull request to `develop` or `main` and on every push to those branches.

## What it checks

`scripts/security-scan.sh` runs `pip-audit` on the Python requirements of this
repository:

- `rabbitmq/requirements.txt`
- `rabbitmq/tests/requirements-test.txt`

The job fails if `pip-audit` reports a known vulnerability that is not listed in
`security/accepted-vulnerabilities.txt`.

## Policy: dependencies are not changed to pass the scan

If the scan fails because of a vulnerability, the team does **not** change or pin
dependencies just to make the check green. Instead the advisory is reviewed and, if the
risk is acceptable, added to the accepted list below with a reason. This is the same
approach as ADR-14 in `edura-documents` for the frontend (`audit-ci.jsonc`) and keeps
the deployed dependency tree unchanged.

## How to bypass a failing check

1. Find the advisory ID in the job log (for example `PYSEC-2024-1234` or
   `GHSA-xxxx-xxxx-xxxx`).
2. Decide whether it is acceptable: is the vulnerable code reachable in this repo?
3. Add one line to `security/accepted-vulnerabilities.txt`:

   ```
   <advisory ID>  <reason; owner; review date>
   ```

4. Raise a pull request. The reviewer must agree with the reason. Never accept an
   advisory without a written reason and a review date.
5. Remove the line once the dependency is fixed or no longer used.

Accepted advisories are printed in the job log on every run, so they stay visible. They
do not fail the build; any **new** advisory does.

## Currently accepted advisories

None. The list is kept in `security/accepted-vulnerabilities.txt`, which is the single
source of truth. Update this section when an advisory is accepted:

| Advisory | Package | Reason | Owner | Review date |
|---|---|---|---|---|
| (none) | | | | |

## Lint & Format job

The same workflow also runs the **Lint & Format** job on every push to any branch:

| Check | Files | Config |
|---|---|---|
| yamllint | Docker Compose, Kubernetes manifests, workflows | `.yamllint.yml` |
| hadolint | `rabbitmq/Dockerfile` | defaults |
| shellcheck | `scripts/*.sh`, `postgres/*.sh` | fails on warnings and errors |
| Ruff + Black | `rabbitmq/`, `nginx/` | `pyproject.toml` (same rules as `edura-backend`) |

Run the Python checks locally with `ruff check rabbitmq nginx` and
`black --check rabbitmq nginx`.
