# manifests/ — what you must produce

This is a **checklist, not an answer key.** The K8s lesson's reference manifests
(`cicd_dockerized/k8s-lesson/manifests/`) target a single-node laptop cluster. Here you
re-author them for real multi-node infra and add the hardening the brief requires.

Produce (raw YAML, a Helm chart, or kustomize overlays — your call):

**App**
- [ ] `namespace`
- [ ] `ConfigMap` (non-secret) + `Secret` (secret, NOT committed in plaintext — see gitops/ + Sealed Secrets stretch)
- [ ] Postgres `StatefulSet` + headless `Service` + PVC on the cluster's storage class
- [ ] backend `Deployment` (2+ replicas) + `Service` named **`backend`** (the frontend proxies `/api` → `backend:5000`)
- [ ] frontend `Deployment` (2+ replicas) + `Service`
- [ ] migration `Job` (run-once) — replicas must NOT migrate
- [ ] `Ingress` (+ `api.` host or `/api` path) with cert-manager TLS on your real domain

**Make it production, not a demo**
- [ ] `topologySpreadConstraints` / pod anti-affinity so replicas land on different nodes
- [ ] probes (startup/readiness/liveness) + `resources.requests`/`limits` on every container
- [ ] `strategy.rollingUpdate.maxUnavailable: 0`
- [ ] pinned image tags (no `:latest`)
- [ ] ≥3 Advanced: HPA / NetworkPolicy / PDB+graceful-shutdown / observability / securityContext

**Platform (install once, document how):**
- [ ] ingress controller, cert-manager + ClusterIssuer, metrics-server, Argo CD

Every box you tick must have matching evidence in `docs/EVIDENCE/`.
