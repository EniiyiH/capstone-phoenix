# infra/ansible/ — turn bare VMs into a k3s cluster

Reuse your provisioning role and add k3s. Roles, not one giant playbook.

**Roles:**
- `hardening` — non-root user, SSH-keys-only, firewall, (optional) fail2ban. You have this already.
- `k3s-server` — install k3s on the control-plane; capture `/var/lib/rancher/k3s/server/node-token`.
- `k3s-agent` — join each worker with that token + the server's private IP.

**Inventory:** generate (or hand-write) from Terraform outputs — one `server` host, N `agents`.

**Requirements:**
- Idempotent: a second `ansible-playbook` run reports `changed=0`.
- Fetch `/etc/rancher/k3s/k3s.yaml` back to your machine, rewrite `server:` to the public IP,
  save as a gitignored kubeconfig.

**Acceptance:**
```bash
kubectl get nodes -o wide      # control-plane + all workers = Ready
```
Disable k3s's bundled Traefik (`--disable traefik`) only if you install ingress-nginx instead —
either is fine, just be consistent and document it in ARCHITECTURE.md.
