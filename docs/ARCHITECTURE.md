# Architecture (fill this in)

## 1. Topology diagram
> Draw it (ASCII, Excalidraw, draw.io — anything). Show: your nodes, where each TaskApp
> tier runs, the ingress controller, and the request path.

```
[ replace with your diagram ]

  Internet ──DNS──▶ taskapp.<you>.dev / api.<you>.dev
        │
        ▼
  ingress controller (node: ____)  ──TLS terminated by cert-manager──┐
        │                                                            │
        ▼                                                            ▼
  frontend Service ──▶ frontend Pods (nodes: __, __)        backend Service ──▶ backend Pods (nodes: __, __)
                              │  /api proxy                              │
                              └────────────────────────────────────────▶│
                                                                         ▼
                                                          postgres Service ──▶ postgres-0 (PVC on node __)
```

## 2. Node & network
- Nodes (role, size, AZ/region): …
- CIDR / subnet choices and why: …
- Firewall: what's open to the world, what's internal, and why `6443` is closed: …

## 3. Request flow (one paragraph)
> DNS → ingress → TLS → frontend → /api → backend → Postgres. Be specific about names/ports.

## 4. The single-server assumptions you fixed  ← graders look here
> For each, name the assumption that was safe on one box but breaks on a cluster, and the
> K8s mechanism you used. Minimum: migrations, persistent storage, traffic routing,
> self-healing, zero-downtime deploys, secrets.

| Single-server assumption | Why it breaks at scale | How you fixed it |
|---|---|---|
| migrate-on-boot in the entrypoint | 2+ replicas race on `alembic upgrade head` | … |
| named volume on the host | Pods reschedule across nodes | … |
| `ports:` published on the host | many Pods, many nodes, one front door needed | … |
| … | … | … |

## 5. Choices & trade-offs
- Raw YAML vs Helm vs kustomize — why: …
- ingress-nginx vs k3s Traefik — why: …
- CNI / NetworkPolicy enforcement — what and why: …
- Secrets approach (out-of-band vs Sealed/External Secrets) — why: …
