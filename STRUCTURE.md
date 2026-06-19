# Repo structure

Build out this layout. The stub READMEs in each folder tell you what goes there. You may
swap raw `manifests/` for a Helm chart or kustomize overlays — say which in ARCHITECTURE.md.

```
capstone-phoenix/
├── README.md                 # the brief (read first)
├── STRUCTURE.md              # this file
├── .gitignore                # MUST cover state, kubeconfig, .env, secrets
│
├── infra/
│   ├── terraform/            # 3+ nodes, network, firewall, REMOTE state
│   │   └── README.md
│   └── ansible/              # roles: hardening, k3s-server, k3s-agent
│       └── README.md
│
├── manifests/                # OR helm/ OR kustomize/ — TaskApp + platform
│   └── README.md             # the checklist of objects you must produce
│
├── gitops/                   # Argo CD Application(s) pointing at manifests/
│   └── README.md
│
└── docs/
    ├── ARCHITECTURE.md       # diagram + "which single-server assumption each fix solves"
    ├── RUNBOOK.md            # zero -> running, scale, roll back, recover
    ├── COST.md               # itemized monthly cost + how you'd halve it
    └── EVIDENCE/             # screenshots/logs that prove each claim
```

## Definition of done
A teammate clones this repo, follows `docs/RUNBOOK.md`, and ends up with the *same* live,
HTTPS, multi-node, GitOps-managed TaskApp — without asking you anything.
