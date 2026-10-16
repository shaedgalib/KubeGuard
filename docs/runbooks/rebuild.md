# Runbook: lab lifecycle and rebuild (P1-U11, P1-U13)

Five commands run the whole lab. They are thin wrappers over the targets of the earlier units (`infra/cluster.sh`), so each step can also be run by hand as described in [lab-operations.md](lab-operations.md). Every stage prints its own duration, and the log of each run is kept outside the repository in `~/.local/share/kubeguard/rebuild-logs/`.

| Command | What it does | Destroys data? |
|---|---|---|
| `make up` | Starts the networks and the node VMs, waits until the API answers and all nodes are `Ready` (for example after a host reboot) | No |
| `make down` | Shuts the node VMs down gracefully, workers first; the disks and networks stay | No |
| `make reset CONFIRM=yes` | **Destroys** the three node VMs, their disks and their VM snapshots, and creates fresh VMs from `kg-template-vm` | **Yes** |
| `make cluster` | From clean VMs to the full cluster (stages below). Safe to run again on a running cluster: every stage is idempotent | No |
| `make rebuild CONFIRM=yes` | `reset` then `cluster`, with the total time against the 40 minute target | **Yes** |

`reset` and `rebuild` refuse to run without `CONFIRM=yes`.

## The stages of `make cluster`

1. Networks: `kg-isolated-network` and `kg-internet-access-network` are created or started if needed.
2. Node VMs started; the internet window is attached (`internet0`), because packages and images are downloaded.
3. Ansible installed in `.venv` if missing.
4. Kubernetes with Ansible: common, containerd, Kubernetes packages, `kubeadm init`, `kubeadm join`, then the hardening role (P2-U2, P2-U6: hardened kubeadm configuration, kubelet settings, file modes, audit policy, encryption of Secrets; see [hardening.md](hardening.md)). The project kubeconfig `~/.kube/kubeguard.kubeconfig` is written again.
5. Gateway API CRDs, then Cilium and Hubble (the nodes become `Ready`).
6. Load balancer pool and L2 policy, local-path storage.
7. Monitoring: Grafana admin Secret (a new random password; saved to `~/.config/kubeguard/grafana-admin-password`), then Prometheus and Grafana.
8. Kyverno and its three policies ([access-control.md](access-control.md); Kyverno images are pulled in the internet window), then the sample app, then the Pod Security labels and the default service account settings.
9. Checks: Cilium status; the storage, load balancer and Gateway test of P1-U6 and a request to each address from the host; the monitoring test (U7); the sample app and Hubble flows (U8); the hardening tests (`make test-hardening`).

A failing stage stops the run, prints the stage times so far and names the stage. Fix the cause and run `make cluster` again: stages that are done change nothing.

## What is not rebuilt

- The template VM `kg-template-vm` (P0-U6). `reset` needs it; build it with `make template-vm-create` if it is missing.
- Files outside the cluster: etcd snapshots (`~/.local/share/kubeguard/etcd-backups/`), the copies of the encryption keys (`~/.local/share/kubeguard/encryption-keys/`; a rebuild creates a new key, so keep the old one while old snapshots matter), the Grafana password file (rewritten by `cluster`), the repository.
- Everything inside the old cluster: workload data, Prometheus data and Secrets are gone after `reset`.

## After a rebuild

- The nodes are in the build window (`internet0` attached). Close it before any attack work: `make vms-isolate`, then `make isolated-network-test` and `make vms-test`.
- Take a VM restore point if you want one: `make vms-snapshot`.

## If something fails

- `reset` says `kg-template-vm` is missing: `make template-vm-create`.
- The Ansible stage fails on a node: `make vms-status`, then repeat `make cluster`.
- Image pulls fail: the internet network is down or `internet0` is detached: `make internet-network-up`, `make vms-attach-internet`.
- A check stage fails after the build: run that check by hand (`make net-test-u6`, `net-test-u7`, `net-test-u8`) and read the failing line.
