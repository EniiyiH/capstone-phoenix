# infra/terraform/ — provision the nodes

Seed this from your single-EC2 Terraform and grow it to a small fleet.

**Must produce:**
- 1 control-plane VM + **2+ worker VMs** (small instances are fine).
- Modules: `network`, `security_group`/firewall, `compute`.
- **Remote state** (S3 + DynamoDB lock, GCS, etc.) — no `*.tfstate` in git.
- Firewall: world-open only `80`/`443`; `22` from your IP; `6443` and node ports NOT public.
- `outputs.tf`: control-plane + worker IPs (public for SSH, private for k3s join) for Ansible.
- Everything parameterized in `variables.tf`; ship a `terraform.tfvars.example` (real one gitignored).

**Acceptance:** `terraform apply` from clean → you can SSH to every node; `terraform destroy`
leaves nothing behind. Re-running `plan` after apply shows no drift.

> Keep infra lean: one k3s server is fine — you do NOT need a multi-master/HA control plane.
> The difficulty in this capstone lives in Kubernetes, not the control plane.
