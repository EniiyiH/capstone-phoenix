# Cost (fill this in)

This echoes the Docker lesson's "why one server" thread — except now the answer to "is the
extra cost worth it?" is yours to argue.

## Monthly itemized cost
| Item | Spec | Qty | $/mo |
|---|---|---:|---:|
| control-plane VM | … | 1 | … |
| worker VMs | … | 2+ | … |
| load balancer / elastic IP | … | … | … |
| block storage (PVC) | … | … | … |
| object storage (state, backups) | … | … | … |
| DNS / domain | … | … | … |
| **Total** | | | **$…** |

## Compared to the single-server Compose+Portainer deploy
- That stack cost roughly: $…
- This cluster costs: $…
- **What the extra spend buys** (be honest — tie to §0 of the brief): HA, autoscale,
  zero-downtime, multi-node self-healing. When is it NOT worth it? …

## How I'd halve this
> One concrete paragraph: spot/preemptible workers? smaller control-plane? k3s on 2 nodes?
> shared ingress? …
