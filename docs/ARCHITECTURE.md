# Architecture — Phoenix: TaskApp on Real Kubernetes

## 1. Overview

TaskApp runs on a 3-node k3s cluster on AWS EC2: 1 control-plane + 2 workers, provisioned
with Terraform, configured with Ansible, and deployed as plain Kubernetes manifests
(`manifests/`) reconciled continuously by Argo CD (GitOps). TLS is terminated at an Ingress
(Traefik) using a real Let's Encrypt certificate on `taskapp.eniiyi.name.ng`.

**Deployment format:** raw Kubernetes manifests, not Helm or Kustomize. This project has a
single environment (no dev/staging/prod split), so templating/overlay tooling would add
indirection without a corresponding benefit. Manifests are applied in a fixed order
(namespace → config/secret → data layer → migration → app layer → networking/policy) and
that order is enforced by Argo CD's sync, not by manual sequencing.

## 2. Node topology

| Node | Instance type | Role | Why |
|---|---|---|---|
| control-plane | t3.small | k3s server, Argo CD, cert-manager | Single control-plane — README explicitly does not require HA etcd/multi-master. Kept at t3.small (not resized to t3.medium) by switching to Argo CD's `core-install.yaml`, which drops the UI, Dex, and notifications-controller to fit the memory budget. |
| worker-1 | t3.small | Application workloads | Runs a mix of backend/frontend/Postgres, whichever the scheduler and topology spread place here |
| worker-2 | t3.small | Application workloads | Same as worker-1 |

All 3 nodes are provisioned by Terraform (`infra/terraform/modules/compute`), with the AMI
resolved dynamically (latest Ubuntu 22.04) rather than hardcoded, and configured by Ansible
roles (`hardening`, `k3s-server`, `k3s-agent`) applied via `infra/ansible/site.yml`.

## 3. Networking

### Layers, outside in
1. **DNS** — `taskapp.eniiyi.name.ng` A record points at the control-plane's current public IP (managed at WhoGoHost). This is the most operationally fragile link in the chain — see RUNBOOK.md for what breaks when the IP changes.
2. **AWS Security Group** — least-privilege: 22 (SSH, restricted to admin IP), 80/443 (public), 6443 (Kubernetes API, restricted to admin IP), plus an all-traffic self-referencing rule for node-to-node cluster communication. 6443 is never open to `0.0.0.0/0`.
3. **Host firewall (ufw)** — a second, independent layer on each node, mirroring the security group's intent but enforced at the OS level. This project hit a real bug twice: ufw was initially only opened for 22/80/443 and the VPC CIDR, which silently blocked (a) worker-to-control-plane k3s join traffic on 6443, and (b) admin laptop access to 6443 for `kubectl`, even though the AWS security group correctly allowed both. Both had to be fixed explicitly in the `hardening` Ansible role. **Lesson: a security-group rule and a host-firewall rule are independent; matching one does not imply the other matches.**
4. **Kubernetes NetworkPolicy** — default-deny ingress in the `taskapp` namespace, with explicit allow rules: frontend ← anywhere (public entry), backend ← frontend only, postgres ← backend only. **Caveat:** k3s ships Flannel as its default CNI, which does not enforce NetworkPolicy. These policies are written and applied for correctness and to express intended access control, but are not actively enforced at the network layer in this deployment. Enforcing them would require switching to Canal or Calico, which was judged out of scope given project time and the risk of destabilizing a working cluster late in the build.

### Request flow

```
Browser
  → DNS (taskapp.eniiyi.name.ng → control-plane public IP)
  → Ingress (Traefik, TLS terminated here, cert from cert-manager + Let's Encrypt)
  → frontend Service → frontend Pod (nginx, serves the SPA)
  → backend Service → backend Pod (Flask, /api/* routes)
  → postgres Service (headless) → postgres-0 Pod → PVC (local-path storage)
```

Both frontend and backend are 2-replica Deployments spread across the 2 worker nodes via
`topologySpreadConstraints` (`whenUnsatisfiable: DoNotSchedule`), so no single node loss
takes down 100% of either tier. Postgres is a single-replica StatefulSet — see §4 for why
this is an accepted trade-off, not an oversight.

## 4. Single-server assumptions, and what fixes each one

The original single-EC2/Portainer deployment made assumptions that silently held on one
box and had to be deliberately un-made for a real multi-node cluster:

| Assumption (single-server) | Breaks because | Fix in this deployment |
|---|---|---|
| Postgres data lives on local disk | A Pod can be rescheduled to any node at any time | StatefulSet + PVC (network-attached-style volume via `local-path` provisioner) — proven by killing `postgres-0` and confirming the row inserted beforehand survives |
| One replica per service is enough | A single node failure takes the whole tier down | 2 replicas per tier, `topologySpreadConstraints` forcing them onto different nodes |
| Migrations run in the app's entrypoint | 2+ replicas starting concurrently race on `alembic upgrade head` | Migrations moved to a Kubernetes `Job`, run once, to completion, before any replica starts |
| A rolling deploy can drop connections briefly | Users on a live multi-replica service would see real errors, not just a personal restart | `maxUnavailable: 0, maxSurge: 1` on both Deployments — verified via a continuous curl loop through a live rollout with zero non-200 responses (`docs/EVIDENCE/zero-downtime.log`) |
| One admin manually deploys via SSH/Portainer webhook | No single source of truth; manual drift is invisible and unrecoverable | Argo CD watches `manifests/` in git and reconciles continuously, with `selfHeal: true` — a manual `kubectl scale` was deliberately introduced during testing and Argo CD reverted it automatically within its reconciliation interval |
| Firewall is "one rule at the edge" | Cloud firewall and host firewall are independent; a compromised host still needs its own restrictions | Two independent layers (AWS SG + ufw) enforcing the same intent |
| Fixed replica count sized for average load | Real traffic spikes; over-provisioning constantly wastes cost, under-provisioning drops requests | HPA on the backend (CPU-based, 2–6 replicas) — demonstrated scaling 2 → 6 under a synthetic load generator |

## 5. Why Postgres is not (yet) highly available

Running a single Postgres replica is a deliberate, documented trade-off, not an omission.
True HA Postgres (e.g. Patroni-managed replicas, or a managed RDS instance) was listed in
the README as a **stretch** item, not Core or Advanced. Given the project's 3-week scope and
the added operational complexity of managing Postgres replication/failover correctly, a
single StatefulSet replica with a persistent volume was chosen. The risk this accepts: if
the node running `postgres-0` is lost, there is a brief availability gap while Kubernetes
reschedules the Pod and reattaches its PVC — data is not lost (proven), but the database is
briefly unavailable. This is the single largest remaining single-point-of-failure in the
architecture, and is called out here intentionally rather than glossed over.

## 6. Security hardening applied

- `runAsNonRoot: true` + dropped Linux capabilities + `seccompProfile: RuntimeDefault` on the backend container, which runs as a non-root `appuser` in its base image.
- The frontend container **cannot** run `runAsNonRoot: true` as-is — its base nginx image binds to port 80 and requires root to do so. Frontend still gets `seccompProfile`, `allowPrivilegeEscalation: false`, and dropped capabilities, but not the non-root constraint. Fixing this fully would require a custom nginx image (e.g. rebuilt to listen on an unprivileged port), which was out of scope since the app images were provided pre-built, not built by this project.
- `readOnlyRootFilesystem` is left `false` on both — both the Flask app and nginx write to their filesystem at runtime (temp files, caches, PID files), and setting this to `true` without adapting the image would crash-loop both containers.

## 7. GitOps

Argo CD (`core-install.yaml` — the lightweight distribution, chosen specifically because the
full install's additional components, Dex/notifications-controller/UI-server, exhausted
available memory on the `t3.small` control-plane during initial testing) watches the
`manifests/` folder in this repo's `main` branch. `syncPolicy.automated` with `selfHeal: true`
and `prune: true` means: any drift from what's committed (manual edits, manual scaling, manual
deletion) is automatically reverted, and anything removed from git is removed from the
cluster. The AppProject `default` had to be created explicitly, since `core-install.yaml`
(unlike the full manifest) does not bootstrap it automatically.
