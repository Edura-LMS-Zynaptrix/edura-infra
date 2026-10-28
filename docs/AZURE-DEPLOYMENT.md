# Deploying EDURA to Azure AKS — step by step

This guide implements the deployment the project documents ask for:

- **DDP-#12**: AKS cluster and ACR registry, verified with a hello-world pod from ACR, and GitHub Actions able to reach the cluster.
- **DDP-#18**: GitHub Actions builds every image, tags it with the git SHA, pushes it to ACR, and deploys to **staging on every push to `develop`**.
- **DDP-#24**: An E2E smoke test runs against staging after each deploy.
- **Guideline Ch. 7**: Production deploys on merge to `main` **with manual approval**, and secrets live in GitHub Secrets.
- **Guideline §9.1**: The panel demo runs on the deployed staging URL.

Where this differs from SDS Chapter 8 (region, node size, TLS edge, GitHub Actions instead of Azure DevOps), the reasons are recorded in **`edura-documents/ADR-13-azure-deployment-adjustments.md`**. Review it with the supervisor, as guideline §1.3 requires.

> **Minimum-resource setup.** To save free-trial credit, this guide provisions the smallest cluster that runs
> EDURA: **one `Standard_D2als_v7` node (2 vCPU, 4 GB)** running **staging only**. That's about **US$95/month**,
> compared with ~US$280+ for the SDS sizing. Production is fully wired into the pipeline but switched off
> until you need it; see **Part F**. Record this sizing decision in your ADR.

It assumes you have never used Azure before. Commands run in **Git Bash**, from `D:\github\edura\edura-infra`, unless a step says otherwise.

| | Staging | Production |
|---|---|---|
| URL | https://staging.eduralms.com | https://eduralms.com |
| Deployed when | every push to `develop` (any of infra / backend / frontend) | push to `main`, after a reviewer approves (**off until Part F**) |
| Kubernetes namespace | `edura-staging` | `edura-production` |
| GitHub environment | `staging` | `production` (required reviewers) |

---

## 0. The big picture

```
 GitHub (Edura-LMS-Zynaptrix)
 ├─ edura-backend  ──push develop/main──┐  (trigger-deploy.yml)
 ├─ edura-frontend ──push develop/main──┤
 └─ edura-infra    ──push develop/main──┴─▶ deploy.yml
                                           1. build 11 service images + rabbitmq-setup + frontend (tag = git SHA)
                                           2. push to ACR (eduracr…azurecr.io)
                                           3. deploy to AKS namespace, wait for every pod, health-check
                                           4. (staging) run edura-tests/smoke/critical_path.py

 Azure (eastus) ── resource group edura-rg
 ├─ ACR   eduracr…            images
 └─ AKS   edura-aks (1 × Standard_D2als_v7, 30 GB OS disk)
     └─ edura-staging     Caddy (HTTPS) → nginx gateway → 11 services + frontend, RabbitMQ, Redis
        (edura-production: same manifests, added later — Part F)

 Neon PostgreSQL (AWS us-east-1) — one database per service, unchanged
```

**Files involved**

| File | Purpose |
|---|---|
| `scripts/provision-aks.sh` | Creates the resource group, ACR, AKS and the staging static IP (#12) |
| `scripts/setup-github-oidc.sh` | Lets GitHub Actions sign in to Azure without a password; writes the 6 Azure secrets |
| `scripts/sync-github-secrets.sh` | Uploads the 11 service `.env` files as GitHub environment secrets |
| `.github/workflows/deploy.yml` | The build → push → deploy → health → smoke pipeline (#18, #24) |
| `.github/workflows/ci.yml` | Its `deploy-staging` and `deploy-prod` jobs now call `deploy.yml` |
| `k8s/base/` | Manifests shared by both environments, plus `nginx.conf` for the cluster |
| `k8s/staging/`, `k8s/production/` | Namespace, domain and IP name for each environment |
| `scripts/deploy-env.sh` | The deploy step itself (used by the pipeline and by manual deploys) |
| `scripts/deploy-aks.sh` | Manual build and deploy from your PC: an emergency fallback |
| `edura-backend` and `edura-frontend` `/.github/workflows/trigger-deploy.yml` | Start a deploy when code merges in those repos |
| `edura-frontend/Dockerfile`, `edura-backend/.dockerignore` | Production frontend image; keeps `.env` out of images |

**Cost (eastus, approximate).**

| Item | US$/month |
|---|---|
| 1 × Standard_D2als_v7 VM (US$0.0804/hour) | ~59 |
| 30 GB OS disk + 2 small data disks (RabbitMQ, certificates) | ~6 |
| Standard load balancer (AKS always creates one) | ~18 |
| 2 static IPs (cluster outbound + staging) | ~7 |
| ACR Basic | ~5 |
| AKS control plane (Free tier) | 0 |
| **Total** | **~95** (about US$3/day) |

`az aks stop` (Part E) stops the VM, the biggest part of the bill, whenever nobody is using staging.

> ⚠️ **Free trial limits.** The trial lasts 30 days or until the credit runs out, whichever comes first.
> After that Azure **disables** your resources unless you upgrade to pay-as-you-go
> (Portal → Subscriptions → *Upgrade*). Your demo is in week 16, so plan the upgrade (or the
> cluster's start date) accordingly. You keep the remaining credit when you upgrade.

---

## Part A — One-time setup

### Step 1. Install the tools

Docker Desktop, Git Bash and kubectl are already installed. In **PowerShell**, add:

```powershell
winget install --exact --id Microsoft.AzureCLI
winget install --exact --id GitHub.cli
```

Reopen the terminal, then in Git Bash check:

```bash
az version && gh --version && kubectl version --client && docker version
```

### Step 2. Sign in and prepare the subscription

```bash
az login                         # browser sign-in to your Azure account
az account show -o table         # the subscription you will be billed on
gh auth login                    # GitHub.com → HTTPS → login with browser (use your org-admin account)
```

A new subscription has to enable each Azure service once (1–2 minutes each, and safe to repeat):

```bash
for ns in Microsoft.ContainerService Microsoft.ContainerRegistry Microsoft.Compute \
          Microsoft.Network Microsoft.Storage Microsoft.OperationalInsights; do
  az provider register --namespace $ns --wait
done
```

Check the vCPU quota. Both lines need a **Limit of at least 2**:

```bash
az vm list-usage --location eastus -o table | grep -E "Total Regional vCPUs|Standard Dalsv7 Family"
```

If the list is empty, the provider registration above hasn't finished; run it again.

### Step 3. Provision AKS and ACR (DDP-#12)

Choose a **registry name**. It must be globally unique, 5–50 lowercase letters or digits, with no dashes.
Issue #12 suggests `eduracr<team-initials>`.

```bash
az acr check-name --name eduracrzynaptrix -o table      # NameAvailable must be True
export ACR_NAME=eduracrzynaptrix                          # ← your choice; reuse it below
```

Create everything (10–15 minutes):

```bash
cd /d/github/edura/edura-infra
ACR_NAME=$ACR_NAME ./scripts/provision-aks.sh
```

The defaults are the minimum setup: 1 × `Standard_D2als_v7`, a 30 GB OS disk, and a static IP for staging only.
(Free-trial subscriptions can't use B-series sizes for AKS, so `Standard_B2s` is rejected with
*"The VM size of Standard_B2s is not allowed in your subscription"*. D2als_v7 is the cheapest allowed 2-vCPU size.)
At the end the script prints that IP. **Write it down**:

```
  edura-staging-ip = 20.x.x.x
```

**Verify the acceptance criteria of #12:**

```bash
# AC1 — Ready node(s). #12 asks for 2 or more; the minimum setup uses 1 (justify in your ADR)
kubectl get nodes

# AC2 + AC3 — a pod running from an image pulled out of YOUR ACR
az acr import --name $ACR_NAME --source mcr.microsoft.com/azuredocs/aci-helloworld:latest --image hello-world:v1
sed "s|mcr.microsoft.com/azuredocs/aci-helloworld:latest|$ACR_NAME.azurecr.io/hello-world:v1|" k8s/hello-world.yaml | kubectl apply -f -
kubectl get pods -l app=hello-world          # Running (not ImagePullBackOff)
kubectl logs -l app=hello-world
kubectl delete deployment hello-world-deployment && kubectl delete service hello-world-service
```

> **"VM size not allowed" or quota errors:** the error lists every size your subscription accepts. Good 2-vCPU
> picks are `NODE_SKU=Standard_D2as_v7` (8 GB, ~US$66/month VM) and `NODE_SKU=Standard_D2as_v4` (8 GB, ~US$70);
> put the setting in front of the command. After a failed run, delete the half-created
> cluster with `az aks delete -g edura-rg -n edura-aks --yes` and run it again.

### Step 4. Point the domain at Azure

At the DNS provider for **eduralms.com** (where you added the Resend records), add:

| Type | Name / Host | Value | TTL |
|---|---|---|---|
| A | `staging` | *edura-staging-ip* | 300 |

(The root `eduralms.com` record for production is added in Part F.)

Keep the existing Resend records (MX/TXT/DKIM) as they are. Check propagation, which usually takes a few minutes:

```bash
nslookup staging.eduralms.com
```

It must return the IP you wrote down **before the first deploy**. Caddy can only obtain the HTTPS
certificate once DNS points at it.

### Step 5. Connect GitHub to Azure (DDP-#12 AC4)

```bash
GITHUB_ORG=Edura-LMS-Zynaptrix ACR_NAME=$ACR_NAME ./scripts/setup-github-oidc.sh
```

This writes these secrets to **edura-infra**: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`,
`ACR_LOGIN_SERVER`, `AKS_CLUSTER_NAME` and `AKS_RESOURCE_GROUP`. These are the 5 listed in #12, plus the
subscription ID that `azure/login` needs.
No password or kubeconfig is stored. GitHub proves its identity to Azure on each run through OIDC.

### Step 6. A token for cross-repo access

The infra pipeline checks out `edura-backend`, `edura-frontend` and `edura-tests`. The backend and frontend
repos start deploys in `edura-infra`. Both need a fine-grained personal access token.

1. GitHub → your avatar → **Settings → Developer settings → Fine-grained tokens → Generate new token**
2. **Resource owner:** `Edura-LMS-Zynaptrix`. **Expiration:** after the demo date.
3. **Repository access:** `edura-backend`, `edura-frontend`, `edura-tests`, `edura-infra`
4. **Permissions:** *Contents: Read*, *Metadata: Read*, *Actions: Read and write*
5. Generate, copy it, then:

```bash
gh secret set GH_PAT             --repo Edura-LMS-Zynaptrix/edura-infra      # paste the token
gh secret set INFRA_DEPLOY_TOKEN --repo Edura-LMS-Zynaptrix/edura-backend    # same token
gh secret set INFRA_DEPLOY_TOKEN --repo Edura-LMS-Zynaptrix/edura-frontend   # same token
```

If the org requires approval for fine-grained tokens, approve it under
**Org Settings → Personal access tokens → Pending requests**.

### Step 7. Create the GitHub environments

In **github.com/Edura-LMS-Zynaptrix/edura-infra → Settings → Environments**:

| Environment | Settings |
|---|---|
| `staging` | No protection rules. *Deployment branches:* `develop` (plus `main` is fine) |

Production's environment is created later, in Part F.

Add the Google client ID as a repository **variable** (not a secret, since it is public):

```bash
gh variable set GOOGLE_CLIENT_ID --repo Edura-LMS-Zynaptrix/edura-infra \
  --body "694837936576-c04s27dpm6v68ablmu3hlo76vdu9bq7g.apps.googleusercontent.com"
```

### Step 8. Upload the service secrets

Each service's `.env` becomes one secret in the environment (`AUTH_SERVICE_ENV`, `USER_SERVICE_ENV`, and so on).
The pipeline overrides `FRONTEND_URL` with the environment's own URL automatically.

**Staging**, from your local `.env` files:

```bash
./scripts/sync-github-secrets.sh staging
```

Run the script again whenever a value changes, then redeploy.

### Step 8b. Set the RabbitMQ password

The broker and all services share one RabbitMQ account named `edura`. Its password comes from the environment secret `RABBITMQ_PASSWORD`; any `RABBITMQ_USER` or `RABBITMQ_PASSWORD` line in a service `.env` is replaced by it. Create a long random password per environment and store it:

```bash
openssl rand -hex 24 | gh secret set RABBITMQ_PASSWORD --env staging --repo <org>/edura-infra
```

The deploy fails early if the secret is missing. On each deploy, `scripts/deploy-env.sh` creates or updates the `edura` user on the broker, restarts the services so they pick up the new secret, and then deletes the default `guest` account. To rotate the password later, change the secret and deploy again.

### Step 9. Outside services

- **Google Cloud Console → APIs & Services → Credentials → OAuth client → Authorized JavaScript origins:**
  add `https://staging.eduralms.com`.
- **PayHere merchant portal:** allow both domains. Notify URLs are
  `https://staging.eduralms.com/api/payments/webhook` (sandbox) and `https://eduralms.com/api/payments/webhook` (live).
- **Resend:** no change. `noreply@eduralms.com` already uses your verified domain.
- **Neon:** no change. It accepts SSL connections from anywhere.

---

## Part B — First deploy (DDP-#18)

### Step 10. Get the files onto `develop`

Follow the branch strategy (guideline §3.2): one feature branch and one PR per repo.

```bash
# edura-infra
cd /d/github/edura/edura-infra
git checkout develop && git pull upstream develop
git checkout -b feature/DDP-18-aks-staging-deploy
git add .github/workflows/ k8s/ scripts/ docs/ README.md .gitignore .gitattributes
git commit -m "ci(deploy): add build-push-deploy pipeline to AKS staging and production

Adds deploy.yml (matrix image build tagged with git SHA, ACR push, AKS deploy,
health checks, staging smoke test), k8s/base + staging/production overlays,
OIDC and secret-sync scripts. Deviations from SDS ch. 8 in ADR-13.

Refs #6 #7 #21"
git push origin feature/DDP-18-aks-staging-deploy
gh pr create --repo Edura-LMS-Zynaptrix/edura-infra --base develop --fill
```

Do the same for:

- **edura-backend**: `.dockerignore`, `.github/workflows/trigger-deploy.yml`
  (`build(docker): exclude .env from images and trigger staging deploy on merge`)
- **edura-frontend**: `Dockerfile`, `.dockerignore`, `.github/workflows/trigger-deploy.yml`
  (`build(docker): add production Dockerfile and deploy trigger`)
- **edura-documents**: `ADR-13-azure-deployment-adjustments.md` (`docs(adr): ADR-13 Azure deployment adjustments`)

**Merge order:** backend and frontend first (their `.dockerignore` and `Dockerfile` must be on `develop` before
the pipeline builds them), then infra.

### Step 11. Watch the pipeline

Merging the infra PR into `develop` starts **Infrastructure CI & Deploy**. Follow it on the repo's **Actions** tab:

1. `RabbitMQ Script Verification` and `Docker Compose Smoke Test` (the existing CI)
2. **Deploy - Staging**, which runs:
   - `Resolve commits`
   - 11 × `Image <service>` plus `Image rabbitmq-setup`, in parallel. The first build takes about 5–8 minutes; later builds are cached.
   - `Deploy staging`: builds the frontend, applies manifests, waits for every pod, checks `/health` on the public URL
   - `E2E smoke test (staging)`

You can also start it by hand: **Actions → Deploy to AKS → Run workflow** (environment `staging`, branch `develop`).
To test before merging, choose your feature branch in the *Use workflow from* dropdown. That run needs a
federated credential for that branch, so in practice merge to `develop` instead.

### Step 12. Verify

```bash
kubectl -n edura-staging get pods          # all Running 1/1; rabbitmq-setup Completed
curl https://staging.eduralms.com/api/auth/health
```

Open **https://staging.eduralms.com**: register, receive the verification email, log in (including with Google),
browse a course. Add the staging URL to the README of each repo (guideline §9.3 and #18 DoD).

---

## Part C — Day to day

### How deploys happen from now on

| You do | What happens |
|---|---|
| Merge a PR into `develop` in **edura-backend** or **edura-frontend** | `trigger-deploy.yml` starts `deploy.yml` in edura-infra, and that commit goes to staging |
| Merge a PR into `develop` in **edura-infra** | `ci.yml` runs the tests, then deploys to staging |
| Push to a `feature/*` branch | CI only. **No deploy** (#18 AC4) |
| Merge `develop` → `main` (release) | Production deploy starts and **waits for approval** in Actions; a reviewer clicks *Review deployments → Approve* |

Images are only built once per commit. Production reuses the exact images staging tested (same SHA), except the
frontend, which is rebuilt with the production URL.

### Releasing to production (2-week plan Day 12)

1. Supervisor sign-off on staging.
2. In each repo, open a PR `develop` → `main`, get one approval (guideline §8.2), and merge.
3. Approve the waiting **Deploy production** job in edura-infra → Actions.
4. Check https://eduralms.com, then tag the release:
   `git tag -a v1.0.0 -m "EDURA v1.0.0" && git push upstream v1.0.0` (in each repo, guideline §3.3).
5. Seed the demo accounts and courses on production (2-week plan Day 12).

### Rolling back

```bash
kubectl -n edura-staging rollout undo deployment/auth-service      # one service, previous version
```

Or rerun an older successful **Deploy to AKS** run from the Actions tab (*Re-run all jobs*).

### Manual deploy (emergency fallback)

If GitHub Actions is down right before a demo, start Docker Desktop and run:

```bash
ACR_NAME=$ACR_NAME ./scripts/deploy-aks.sh staging
```

It builds from your local checkouts, uses your local `.env` files, and deploys the same way the pipeline does.

---

## Part D — Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `azure/login` fails with *AADSTS70021: No matching federated identity* | The run's branch or environment isn't in the list of federated credentials | Deploy from `develop`/`main` only, or add a credential in `setup-github-oidc.sh` |
| `Resolve commits` fails with 404 | `GH_PAT` can't see the repo | Check the token's repositories and permissions (Step 6) |
| `Secret AUTH_SERVICE_ENV is not set` | Step 8 skipped for that environment | `./scripts/sync-github-secrets.sh staging` |
| Pod `CrashLoopBackOff` | The app crashes at start (DB URL, missing env) | `kubectl -n edura-staging logs deploy/<name> --previous` |
| Pod `ImagePullBackOff` | ACR not attached | `az aks check-acr -g edura-rg -n edura-aks --acr $ACR_NAME.azurecr.io` |
| Pod `Pending` with *Insufficient memory/cpu* | The single 4 GB node is full | `kubectl -n edura-staging describe pod <pod>` (events at the bottom). Add a second node: `az aks scale -g edura-rg -n edura-aks --node-count 2` (+~US$60/month) |
| Pods restarting with `OOMKilled`, or the node reports `MemoryPressure` | 4 GB is too tight for your actual usage | Check `kubectl top pods -n edura-staging`. Move to an 8 GB VM: `az aks nodepool add -g edura-rg --cluster-name edura-aks -n pool8gb --mode System --node-count 1 --node-vm-size Standard_D2as_v7 --node-osdisk-size 30`, then `az aks nodepool delete -g edura-rg --cluster-name edura-aks -n nodepool1` |
| Health checks time out, browser shows a certificate error | DNS isn't pointing at the IP yet, or the IP name doesn't match | `nslookup staging.eduralms.com`; `kubectl -n edura-staging logs deploy/caddy`; `kubectl -n edura-staging get svc caddy` (EXTERNAL-IP must be the static IP) |
| `caddy` service stuck `<pending>` | The static IP isn't in the node resource group | Rerun the step 6 part of `provision-aks.sh` |
| Logged out after a page refresh | The site was opened over `http://` | Use `https://`; the refresh cookie is `Secure` |

Useful commands:

```bash
kubectl -n edura-staging get all
kubectl -n edura-staging logs deploy/notification-service -f
kubectl -n edura-staging port-forward svc/rabbitmq 15672:15672    # RabbitMQ UI → http://localhost:15672
```

The Azure portal shows the same information under **Kubernetes services → edura-aks → Workloads**.

---

## Part E — Cost control

```bash
az aks stop  -g edura-rg -n edura-aks      # stops the VMs (biggest cost); static IPs and DNS stay valid
az aks start -g edura-rg -n edura-aks
az group delete --name edura-rg --yes       # deletes EVERYTHING; not reversible
```

Add a budget alert: **Cost Management → Budgets → Add**, for example US$100 with email alerts at 50% and 80%.
Remember to start the cluster before any review or demo, and check the staging URL 2 hours before the panel (2-week plan Day 14).

---

## Known gaps to close before the final demo

1. **Smoke test step 2 (OTP)** uses a fixed `SMOKE_TEST_OTP`, but auth_service has no test-OTP mode yet,
   so the smoke job will fail at step 2 until the backend adds one (or the script reads the OTP another way, see #24 notes).
   The deploy itself is not undone when the smoke job fails.
2. **Enrollment health** isn't reachable through the gateway, because `/api/enrollments` doesn't strip its prefix.
   The pipeline relies on its readiness probe instead. Adding a `/api/enrollments/health` route would let #18's
   "all services return 200" check include it.
3. **Rotate the secrets** shared outside GitHub Secrets: Neon passwords, Cloudinary, Resend, `SECRET_KEY`. Then rerun Step 8.
4. **RabbitMQ credentials** are no longer `guest/guest` (DDP-#73). Each environment needs a `RABBITMQ_PASSWORD` secret; see Step 8b.
5. **Update SDS Chapter 8** to match ADR-13 (guideline §1.3).

---

## Part F — Adding production later

When you need the production URL (2-week plan Day 12, or the final release):

1. **More capacity.** One 4 GB node can't hold two environments. Add a node:
   `az aks scale -g edura-rg -n edura-aks --node-count 2`, or switch to bigger VMs (see the troubleshooting table).
2. **Static IP.** Create the production IP, then point DNS `@` (the root of eduralms.com) at it:
   ```bash
   NODE_RG=$(az aks show -g edura-rg -n edura-aks --query nodeResourceGroup -o tsv)
   az network public-ip create -g $NODE_RG -n edura-production-ip --sku Standard --allocation-method Static
   az network public-ip show -g $NODE_RG -n edura-production-ip --query ipAddress -o tsv
   ```
3. **GitHub environment.** In edura-infra → Settings → Environments → `production`: set **Required reviewers**
   (team lead and/or supervisor), tick **Prevent self-review**, and set *Deployment branches* to `main` only.
   This is the manual approval gate from guideline Ch. 7.2.
4. **Separate data.** Production should not share databases with staging (SDS §8.4). In each Neon project,
   create a branch for staging and point staging's secrets at it, so production keeps the main branch.
   Put the production `.env` values in a folder **outside any repo**, then:
   ```bash
   ENV_SOURCE=/d/edura-prod-env ./scripts/sync-github-secrets.sh production   # auth.env ... admin.env
   ```
   Use real **PayHere merchant credentials** there, not the sandbox `123456`.
5. **Outside services.** Add `https://eduralms.com` to the Google OAuth origins, and set the PayHere notify URL
   to `https://eduralms.com/api/payments/webhook`.
6. **Switch it on:** `gh variable set ENABLE_PRODUCTION --org Edura-LMS-Zynaptrix --body true --visibility all`.
   From then on, a merge to `main` in any repo deploys to production after approval.
