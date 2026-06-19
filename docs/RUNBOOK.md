# Runbook (fill this in — a teammate must rebuild from this alone)

## Provision from zero
```bash
# 1. infra
cd infra/terraform && terraform init && terraform apply
# 2. cluster
cd ../ansible && ansible-playbook -i inventory site.yml
# 3. kubeconfig
export KUBECONFIG=./kubeconfig && kubectl get nodes
# 4. platform (ingress, cert-manager, metrics-server, argocd) — exact commands:
#    ...
# 5. GitOps takes over
kubectl apply -f gitops/   # then Argo syncs the app
```

## Day-2 operations
- **Scale a tier:** … (and note: prefer a git commit so Argo stays the source of truth)
- **Roll back a bad deploy:** …
- **Run a new migration safely:** …
- **Rotate a secret:** …

## Failure recovery (you'll demo one of these live)
- **A worker node dies / is drained:** what happens, what you do, expected recovery time. …
  ```bash
  kubectl drain <node> --ignore-daemonsets --delete-emptydir-data   # the live-demo command
  ```
- **A backend Pod crashloops:** how you diagnose (`logs --previous`, `describe`, events). …
- **A bad migration:** how you recover the DB. …
- **Postgres Pod is rescheduled:** prove the PVC re-attaches and data is intact. …
