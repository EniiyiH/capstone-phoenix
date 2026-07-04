# Runbook — Phoenix: TaskApp on Real Kubernetes

This runbook is written from real incidents hit while building this project, not
hypotheticals. Every command below has actually been run against this infrastructure.

---

## 0. Prerequisites (one-time, per machine)

```bash
# AWS CLI configured
aws configure
aws configure list   # confirm region is set — do not leave it blank

# Terraform >= 1.10 (needed for native S3 lockfile support)
terraform -version

# Ansible, in a venv (system Python often blocks global pip installs)
cd infra/ansible
python3 -m venv .venv
source .venv/bin/activate
pip install ansible

# SSH key pair for the nodes
ssh-keygen -t ed25519 -f ~/.ssh/phoenix-capstone -C "phoenix-capstone"
```

**Every new terminal session, run these two before anything else** — both are common
sources of confusing failures if skipped:

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/phoenix-capstone            # unlocks the passphrase-protected key once per session
```

Add both to `~/.bashrc` to avoid repeating them:
```bash
echo 'eval "$(ssh-agent -s)" > /dev/null' >> ~/.bashrc
echo 'ssh-add ~/.ssh/phoenix-capstone 2>/dev/null' >> ~/.bashrc
```

---

## 1. Zero → running (fresh provision)

```bash
# 1. Bootstrap remote state (once, ever, per AWS account)
cd infra/terraform/bootstrap
terraform init
terraform apply

# 2. Provision infrastructure
cd ../
terraform init
terraform apply           # review the plan: expect 5 (network) + 7 (security) + 4 (compute) resources on first run
terraform output          # note the 4 IPs

# 3. Update Ansible inventory with current IPs
#    edit infra/ansible/inventory.ini — control_plane, workers, private_ip, admin_ip

# 4. Confirm your current IP matches both terraform.tfvars (my_ip) and inventory.ini (admin_ip)
curl -s https://checkip.amazonaws.com

# 5. Configure the cluster
cd ../ansible
ansible all -m ping        # expect 3x "pong" before proceeding
ansible-playbook site.yml  # hardens nodes, installs k3s server + agents, fetches kubeconfig

# 6. Verify
export KUBECONFIG=$(pwd)/kubeconfig
kubectl get nodes          # expect 3 nodes, all Ready

# 7. Deploy the app, in order (order matters — see §2 for why)
cd ../..
kubectl apply -f manifests/00-namespace.yaml
kubectl apply -f manifests/01-configmap.yaml
kubectl apply -f manifests/02-secret.yaml       # generated via kubectl create secret --dry-run, never hand-written with real values
kubectl apply -f manifests/03-postgres.yaml
kubectl apply -f manifests/04-migration-job.yaml
kubectl wait --for=condition=complete job/taskapp-migrate -n taskapp --timeout=60s
kubectl apply -f manifests/05-backend.yaml
kubectl apply -f manifests/06-frontend.yaml

# 8. TLS + Ingress — only after DNS points at the CURRENT control-plane IP
#    (see §5 — DNS update — before this step, every time the control-plane IP changes)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
kubectl get pods -n cert-manager -w     # wait for all Running
kubectl apply -f manifests/08-clusterissuer.yaml
kubectl apply -f manifests/07-ingress.yaml
kubectl get certificate -n taskapp -w   # wait for READY: True

# 9. Advanced-tier resources
kubectl apply -f manifests/09-pdb.yaml
kubectl apply -f manifests/10-networkpolicy.yaml
kubectl apply -f manifests/11-hpa.yaml

# 10. GitOps
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/core-install.yaml --server-side
kubectl get pods -n argocd -w           # wait for all Running
kubectl apply -f gitops/default-project.yaml    # required — core-install does not bootstrap this automatically
kubectl apply -f gitops/taskapp-application.yaml
kubectl get application taskapp -n argocd       # expect Synced / Healthy within ~30s
```

**From this point on, do not `kubectl apply` changes to `manifests/` directly.** Edit the
file, commit, push — Argo CD applies it within its reconciliation interval. Manual
`kubectl apply`/`kubectl edit` against anything in `manifests/`'s scope will be reverted by
`selfHeal`.

---

## 2. Why the deploy order matters (don't skip steps)

- **ConfigMap/Secret before anything that reads them** — Pods read env vars at container start; applying the workload before its config exists just means it starts with missing/empty values.
- **Postgres before the migration Job** — obvious, but the Job will crash-loop with a connection-refused error if Postgres isn't `Running` yet.
- **Migration Job before backend/frontend Deployments** — this is the actual race condition the README warns about. Migrations run in a Job specifically so they execute exactly once, before any replica starts, avoiding 2+ replicas racing on `alembic upgrade head` simultaneously.
- **DNS pointed at the current IP before requesting a cert** — cert-manager's HTTP-01 challenge requires Let's Encrypt to reach `http://<domain>/.well-known/acme-challenge/...` at the IP DNS currently resolves to. If DNS is stale, the challenge fails.
- **`gitops/default-project.yaml` before the Application** — Argo CD's `core-install.yaml` (chosen to fit the t3.small control-plane's memory budget) does not auto-create the `default` AppProject the way the full install does. Without it, the Application fails immediately with `InvalidSpecError`.

---

## 3. Incident: `kubectl` times out / connection refused

**Symptom:** `dial tcp <ip>:6443: i/o timeout`, or `couldn't get current server API group list ... localhost:8080`.

**Diagnosis tree:**

1. **`localhost:8080` in the error** → `$KUBECONFIG` is unset or wrong in this terminal. Fix: `export KUBECONFIG=.../infra/ansible/kubeconfig`. This is the single most common cause — happens every fresh terminal session unless it's in `.bashrc`.

2. **A real IP in the error, timing out** → check, in order:
   ```bash
   curl -s https://checkip.amazonaws.com                 # your current IP
   cat infra/terraform/terraform.tfvars                   # what the AWS security group allows for 6443/22
   grep admin_ip infra/ansible/inventory.ini               # what ufw allows for 6443 on the control-plane
   ```
   All three must match. IPs rotate — if they don't match, update both files with
   the current IP, then:
   ```bash
   cd infra/terraform && terraform apply
   cd ../ansible && ansible-playbook site.yml
   ```

3. **IPs match but it still times out** → the control-plane instance itself may have been
   replaced (destroy/apply cycle gives new IPs). Check:
   ```bash
   grep server infra/ansible/kubeconfig
   cd infra/terraform 
   terraform output control_plane_public_ip
   ```
   If these differ, the kubeconfig is stale. Re-run `ansible-playbook site.yml` to re-fetch it.

4. **SSH also fails, not just `kubectl`** → check the instance is actually running and
   status checks pass:
   ```bash
   aws ec2 describe-instance-status --instance-ids <id> --output table
   nc -zv -w5 <ip> 22
   ```
   If port 22 answers but SSH itself hangs at "banner exchange," suspect the node is
   memory-starved (see §4) rather than a network/firewall issue.

---

## 4. Incident: node/control-plane runs out of memory

**What happened in this build:** installing Argo CD's full `install.yaml` on a `t3.small`
(2GB RAM) control-plane — already running k3s server components — pushed the node into
memory exhaustion. Symptom was SSH connections timing out mid-handshake ("banner exchange"),
not a clean refusal, which made it initially look like a firewall problem instead of a
resource problem.

**Diagnosis:**
```bash
ssh -i ~/.ssh/phoenix-capstone ubuntu@<ip>   # if this succeeds at all
free -h                                       # check available memory, swap usage
kubectl get pods -A -o wide | grep <node>     # what's actually scheduled here
```

**Fix used:** switched from Argo CD's full `install.yaml` to `core-install.yaml`, which
drops the UI server, Dex (SSO), and notifications-controller — reducing the pod count from
~9 to 4 (`application-controller`, `applicationset-controller`, `redis`, `repo-server`).
This fit comfortably within the remaining memory budget without resizing the node.

**Alternative not taken:** resizing the control-plane to `t3.medium`. Rejected to keep cost
down, given the destroy-when-idle workflow already keeps total spend low; the lighter
Argo CD install solved the actual problem without recurring extra cost.

---

## 5. Incident: control-plane IP changed (destroy/apply, or replacement)

Every `terraform destroy` + `terraform apply` cycle produces a **new public IP** (no Elastic
IP is used, deliberately, to avoid the extra always-on cost). This breaks multiple things
downstream, all of which must be fixed, in this order:

```bash
# 1. Re-run Ansible — re-hardens (idempotent, mostly no-ops) and re-fetches kubeconfig
#    with the new IP baked into its server: line
cd infra/ansible
ansible-playbook site.yml

# 2. Re-apply the full manifest stack — a replaced instance means a fresh k3s cluster
#    with no prior state
cd ..
kubectl apply -f manifests/00-namespace.yaml
kubectl apply -f manifests/01-configmap.yaml
kubectl apply -f manifests/02-secret.yaml
kubectl apply -f manifests/03-postgres.yaml     # NOTE: this is a NEW PVC — old data is gone
kubectl apply -f manifests/04-migration-job.yaml
# ...continue through the rest of manifests/ per §1

# 3. Update DNS — the A record for taskapp.<domain> at your registrar must point
#    at the NEW public IP
 cd infra/terraform 
 terraform output control_plane_public_ip
#    update the A record manually at your DNS provider, then confirm propagation:
dig taskapp.<yourdomain> +short

# 4. Re-check cert-manager survived — if the whole instance was replaced, it did not
kubectl get pods -n cert-manager
#    if empty/missing, reinstall:
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
kubectl apply -f manifests/08-clusterissuer.yaml
kubectl apply -f manifests/07-ingress.yaml
kubectl get certificate -n taskapp -w           # wait for READY: True — requires DNS (step 3) to be correct first
```

**Known data loss on instance replacement:** Postgres's PVC uses k3s's default `local-path`
provisioner, which ties storage to the specific node's local disk. If the control-plane (or
whichever node `postgres-0` was scheduled to) is destroyed, that data is gone — this is a
real limitation of `local-path`, not a bug, and is documented in ARCHITECTURE.md.

---

## 6. Incident: migration Job fails with `connection refused` to `localhost`

**Symptom:** `psycopg2.OperationalError: connection to server at "localhost" ... Connection
refused`, when the app should be connecting to the `postgres` Service.

**Cause:** the ConfigMap/Secret didn't actually contain the env var names the app code
reads. This app reads `DATABASE_HOST`/`DATABASE_PORT`/`DATABASE_NAME`/`DATABASE_USER`/
`DATABASE_PASSWORD` (confirmed from `app/__init__.py` and `migrations/env.py`) — not
`POSTGRES_HOST` etc. If those vars are unset, `os.getenv()` returns `None`, and
psycopg2/SQLAlchemy silently fall back to their own default of `localhost:5432`.

**Fix:**
```bash
kubectl get configmap taskapp-config -n taskapp -o yaml    # confirm DATABASE_HOST etc. are present
kubectl get secret taskapp-secret -n taskapp -o jsonpath='{.data}' | tr ',' '\n'   # confirm key names
```
If keys are missing or wrong, edit `manifests/01-configmap.yaml`/`02-secret.yaml`, re-apply,
then re-run the migration Job (delete the old one first — Jobs don't re-run in place):
```bash
kubectl delete job taskapp-migrate -n taskapp --ignore-not-found
kubectl apply -f manifests/04-migration-job.yaml
kubectl logs job/taskapp-migrate -n taskapp
```

**Related:** Postgres itself reads `POSTGRES_USER`/`POSTGRES_PASSWORD` (to
initialize its own user), while the app reads `DATABASE_USER`/`DATABASE_PASSWORD` (to
connect to it). Both must be set with the **same actual value** — a mismatch here (e.g. from
regenerating the Secret and getting two different random passwords) causes an
authentication failure that looks similar but is a different root cause than the one above.
Check with `kubectl logs job/taskapp-migrate` — an auth failure says so explicitly, distinct
from a connection-refused error.

---

## 7. Recovery: worker node dies / is drained

```bash
kubectl get nodes                          # identify a worker node name
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
```

**Expected behavior:**
- Pods on the drained node are evicted and rescheduled onto the remaining worker, respecting the PodDisruptionBudget (`minAvailable: 1` on both backend and frontend) — eviction will not proceed if it would violate this.
- The app should remain reachable throughout (verify with a curl loop, same technique as `zero-downtime.log`).
- If `postgres-0` was on the drained node, expect a brief availability gap while it reschedules and its PVC reattaches — this is the accepted single-replica-Postgres trade-off documented in ARCHITECTURE.md.

**Recovery:**
```bash
kubectl uncordon <node>       # allow scheduling back onto it once it's back
kubectl get pods -n taskapp -o wide   # confirm redistribution
```

---

## 8. Recovery: backend Pod crashlooping

```bash
kubectl get pods -n taskapp
kubectl logs <pod> -n taskapp --previous     # logs from the crashed instance, not the new restart
kubectl describe pod <pod> -n taskapp        # check Events at the bottom for scheduling/probe failures
```
Common causes seen in this build: missing/misnamed env vars (see §6), or a probe hitting the
wrong path/port after a manifest edit.

---

## 9. Recovery: bad migration

```bash
kubectl logs job/taskapp-migrate -n taskapp   # confirm what actually failed
kubectl delete job taskapp-migrate -n taskapp
#    fix the underlying issue (schema conflict, bad migration file, wrong env var), then:
kubectl apply -f manifests/04-migration-job.yaml
kubectl wait --for=condition=complete job/taskapp-migrate -n taskapp --timeout=90s
```
Because migrations run in a dedicated Job rather than the app's entrypoint, a bad migration
never partially runs across multiple racing replicas — it fails cleanly, once, and can be
fixed and re-run in isolation before any backend replica starts.

---

## 10. Recovery: Postgres Pod rescheduled — confirm data integrity

```bash
kubectl delete pod postgres-0 -n taskapp
kubectl wait --for=condition=ready pod/postgres-0 -n taskapp --timeout=60s
kubectl exec postgres-0 -n taskapp -- psql -U taskapp_user -d taskapp -c "SELECT * FROM <table>;"
```
The StatefulSet guarantees the replacement Pod reuses the name `postgres-0` and reattaches
the same PVC — data written before deletion should still be present after. This exact
sequence was run and verified during the build (see `docs/EVIDENCE/pvc-persist.log`).

---

## 11. Cost-saving workflow (destroy when not actively working)

```bash
# End of session
cd infra/terraform
terraform destroy

# Resume
terraform apply
terraform output                              # new IPs
#    update infra/ansible/inventory.ini and terraform.tfvars with the new IP
cd ../ansible && ansible-playbook site.yml
#    re-apply the full manifests/ stack per §1 step 7 onward
#    update DNS per §5 step 3
```
See `docs/COST.md` for the reasoning behind this workflow.
