# P1-U11 and P1-U13 evidence: one-command lifecycle and measured rebuild

Date: 2026-10-15. Branch: `feat/p1-cluster-automation`. Script: `infra/cluster.sh`; procedure: `docs/runbooks/rebuild.md`. Kubernetes 1.36.5, Cilium 1.20.2, nodes at 3 GiB (control plane) and 5 GiB (workers).

Commands were run by the researcher in their own terminal. The assistant ran only short read-only checks, and did not touch the cluster or the VMs while the rebuild ran. All times were measured by the script.

## What was tested

| Test | Result |
|---|---|
| `make reset` without `CONFIRM=yes` | Refuses and destroys nothing (checked by the assistant) |
| `make down`, then `make up` | Worked (reported by the researcher; the output was not kept) |
| `make cluster` on the running cluster (all stages idempotent) | All 17 stages `ok`, 140 s in total, nothing needed fixing |
| `make rebuild CONFIRM=yes` (destroy the node VMs, create clean ones, build everything, run the checks) | All stages `ok`, **810 s (13 min 30 s)** |

## The timed rebuild (`make rebuild CONFIRM=yes`)

```
     0 s  ok       networks
     2 s  ok       destroy the node VMs
   140 s  ok       create clean node VMs
     0 s  ok       networks
     0 s  ok       start the VMs
    13 s  ok       internet window (images and packages)
   231 s  ok       Kubernetes (Ansible: common, containerd, packages, kubeadm init and join)
     2 s  ok       Gateway API CRDs
   180 s  ok       Cilium and Hubble
     0 s  ok       nodes Ready
     0 s  ok       load balancer pool and L2 policy
     0 s  ok       storage (local-path)
     1 s  ok       Grafana admin Secret
   184 s  ok       monitoring (Prometheus, Grafana)
     0 s  ok       save the Grafana password locally
     9 s  ok       sample app
     1 s  ok       check: Cilium status
    14 s  ok       check: storage, load balancer, Gateway (U6)
    32 s  ok       check: load balancer and Gateway answer from the host
     0 s  ok       check: monitoring (U7)
     1 s  ok       check: sample app and Hubble flows (U8)
   810 s  total

rebuild total: 810 s (13 min 30 s); target 2400 s (40 min)
PASS  within the 40 minute target
```

(`networks` appears twice because both `reset` and `cluster` ensure the networks.) The four largest stages are creating the VMs (140 s), Ansible installing Kubernetes (231 s), Cilium and Hubble (180 s) and monitoring (184 s); together they take 735 s of the 810 s, and all other stages together 75 s.

## State after the rebuild (read-only checks by the assistant)

- Nodes: `kg-control-1` (10.77.0.10), `kg-worker-1` (.11), `kg-worker-2` (.12) all `Ready`, v1.36.5.
- 25 pods in the cluster, none outside `Running`/`Completed`.
- Node memory: 2907, 4917 and 4917 MiB (the sizes in `nodes.conf`).
- The log of the run shows `PASS http://10.77.0.201/ answers 200` and `PASS http://10.77.0.202/ answers 200` (the load balancer and the Gateway of the U6 check, from the host).
- No VM snapshots exist any more: `reset` removes them with the VMs.
- A new Grafana admin Secret was created during the build and the local password file was rewritten after it.

## Findings and limits

- This is one measurement on one day, not an average. The nodes were created fresh from the template, so the packages and container images were downloaded during the run; the speed of the host's internet connection affects those stages, and whether the template held any cached images was not checked.
- The stage `check: monitoring (U7)` and `nodes Ready` took 0 s because the services were already up when they ran; they confirm state and do not wait on anything else.
- The rebuild does not close the build window: the nodes keep `internet0` until `make vms-isolate` is run (planned for the end of Phase 1).
- `reset` destroys the VM snapshots, so a restore point has to be taken again after a rebuild (`make vms-snapshot`).
- The etcd restore drill and the node drills were not repeated on the rebuilt cluster.

## Acceptance

| Unit | Check | Result |
|---|---|---|
| P1-U11 | Clean VMs to a Ready cluster with one command (`make rebuild`), plus `up`, `down` and `reset` | Pass |
| P1-U13 | Rebuild time measured and documented, target under 40 minutes | Pass (810 s) |
