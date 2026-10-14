# KubeGuard

From network anomaly detection to cloud-native security: intrusion detection, eBPF observability and LLM-assisted defense on bare-metal Kubernetes.

Status: Phase 0 (foundation) is done. Phase 1 (Kubernetes cluster and networking) is in progress: the three-node cluster runs with Cilium and Hubble, a layer 4 load balancer, Gateway API, local-path storage and a sample app. Monitoring, drills and the one-command rebuild are next.

- Plan: [docs/AIDLC_Master_Plan.md](docs/AIDLC_Master_Plan.md)
- Specs: [docs/specs/](docs/specs/)
- Decisions: [docs/adr/](docs/adr/)
- Lab operations runbook: [docs/runbooks/lab-operations.md](docs/runbooks/lab-operations.md)
- Evidence reports: [docs/reports/](docs/reports/)
- Source plan: [KubeGuard_Research_Plan.md](KubeGuard_Research_Plan.md)
- Assistant conventions: [CLAUDE.md](CLAUDE.md)

All attack work runs in an isolated lab network. No real targets are involved.
