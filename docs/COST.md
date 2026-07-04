# Cost — Phoenix: TaskApp on Real Kubernetes

## 1. What's actually running

| Resource | Type / size | Quantity | On-demand hourly (us-east-1) |
|---|---|---|---|
| EC2 (control-plane) | t3.small | 1 | $0.0208 |
| EC2 (workers) | t3.small | 2 | $0.0208 each |
| EBS (root volume, default 8GB gp3, per instance) | gp3 | 3 | ~$0.0011/hr each (~$0.08/GB-month) |
| S3 (Terraform state) | Standard | 1 bucket, <1MB | Negligible (<$0.01/month) |
| Data transfer out | — | variable | First 100GB/month free (AWS free tier allowance); this project's traffic is far below that |
| DNS | WhoGoHost (registrar) | 1 domain | Already paid annually at purchase, not a recurring cloud cost |
| TLS certificate | Let's Encrypt | — | Free |

No Elastic IP, no NAT Gateway, no Load Balancer, no managed RDS — all of which would add
meaningful recurring cost and none of which this architecture needs (k3s's built-in Traefik
handles ingress; nodes get default ephemeral public IPs; Postgres runs in-cluster).

## 2. Cost if run 24/7

```
3x t3.small compute:     3 × $0.0208/hr × 730 hr/month  = $45.55
3x EBS gp3 (8GB each):   3 × ~$0.64/month                = $1.92
S3 state bucket:                                          ~$0.01
-----------------------------------------------------------------
Total if left running continuously:                       ~$47.50/month
```

This is the cost of treating this like an always-on environment — which it is not. This
project deliberately does not run this way.

## 3. Actual cost, given the workflow used

Throughout this build, the cluster was destroyed (`terraform destroy`) at the end of each
working session and rebuilt (`terraform apply`) at the start of the next, rather than left
running continuously. State (Terraform state in S3, and the git repo itself) persists
across destroy/apply cycles; only the compute (EC2 instances, and by extension anything
running on them — the k3s cluster, Postgres data, Argo CD, etc.) is torn down and rebuilt.

Estimated real usage: roughly 3-4 hours of active work per day across the build period,
rather than 24 hours. That's:

```
3x t3.small:  3 × $0.0208/hr × ~60 active hours (~3 weeks × ~3hr/day) = ~$3.74
EBS:          negligible at this usage level (EBS bills per GB-month regardless of
              instance running state, UNLESS volumes are also deleted with the instance —
              which they are here, since these are default "delete on termination"
              root volumes, not persistent separately-managed volumes)
S3 state:     ~$0.01
-----------------------------------------------------------------------------------------
Estimated actual total for the build period:                                    ~$4-6
```

This is the single biggest cost lever available in this project: **compute is billed by the
hour it exists, not by the hour it's "in use."** A destroyed instance costs nothing at all,
not a reduced rate — so the destroy/rebuild discipline is not a minor optimization, it's
roughly a 90%+ reduction versus leaving the cluster running for the whole 3-week window.

## 4. How I'd cut this in half again

The remaining cost is already small, but if this needed to run as a genuinely long-lived
environment (not a destroy-between-sessions learning project) rather than optimizing the
already-near-zero build cost, the real lever would be **consolidation, not smaller
instances**: k3s's per-node overhead (the k3s agent process itself, plus whatever
DaemonSets run cluster-wide) is largely fixed regardless of node count, so moving from 3
nodes to 2 (1 control-plane doing double duty as a schedulable node, 1 worker) would cut
compute cost by roughly a third while still technically satisfying "multi-node". In a
context without the three nodes constraint - as stated in the readme.md, that would be the first thing I'd change; the second would
be right-sizing further down from t3.small to t3.micro on the workers specifically (not the
control-plane, which needs the headroom for Argo CD) once actual production memory usage is
profiled rather than assumed.
