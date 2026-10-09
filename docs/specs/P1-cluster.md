# P1: Self-hosted Kubernetes cluster and networking

Status: approved
Approved by / date: shaedgalib (researcher), 2026-10-09

## Objective

Build a reproducible three-node kubeadm cluster on the lab VMs, with Cilium (kube-proxy replacement) and Hubble for networking and flow visibility, and baseline monitoring. The whole cluster must rebuild from the repository with one command. Every layer is understood and documented, because Phases 2 to 5 harden it, attack it and collect data from it.

## Hypothesis and metrics

Phase 1 is an engineering phase and has no research hypothesis. It supports the project claims in [research-questions.md](research-questions.md) (RQ1 to RQ3) by providing the platform and the flow, runtime and audit collection points. Measures, all taken from runs on the lab and never estimated:
- Rebuild time from clean VMs to a Ready cluster (target under 40 minutes).
- RAM and disk use of the cluster idle, against the host budget.
- Whether Hubble flows are visible for the sample application.

## Scope

In scope:
- Three VMs created from the P0-U6 base image (`kg-template-vm`) and cloud-init.
- Ansible roles for node preparation, containerd, kubeadm init and join.
- Cilium with kube-proxy replacement, Hubble relay and UI.
- MetalLB (L2), an ingress or Gateway API controller, local-path storage.
- kube-prometheus-stack with short retention.
- Sample application reachable through MetalLB and ingress, with flows visible in Hubble.
- etcd snapshot and restore, node drain, node failure and rejoin drills, with runbooks.
- `make up`, `make down`, `make reset`, `make cluster`.
- ADRs for CNI, load balancer, ingress and storage.

Out of scope: hardening (Phase 2), workloads and attacks (Phase 3), detection (Phase 4), eBPF feature work (Phase 5), LLM work (Phase 6), multi-node production features such as a highly available control plane.

## Design decisions to confirm

Names follow [docs/naming.md](../naming.md). Accepted by the researcher on 2026-10-09 as the working plan for Phase 1. Any change found necessary during the build is recorded under "Amendments" below, and becomes an ADR where it is a major choice. Each decision also becomes an ADR or a note in the relevant unit.

| # | Decision | Proposed default | Why |
|---|---|---|---|
| D1 | Node sizing | Start minimal: control plane 2 vCPU and 2 GiB, workers 2 vCPU and 2 GiB each. Scale to the plan sizes (4 GiB, 8 GiB, 8 GiB) only when a unit needs it (P1-U7 monitoring at the latest) | kubeadm preflight requires at least 2 vCPU on the control plane; the host has limited free RAM; the researcher asked to start small |
| D2 | Node addressing | Fixed addresses from DHCP reservations in `kg-isolated-network.xml` (for example `10.77.0.10` to `.12`), outside the DHCP pool `.100-.199` | Stable names and addresses for kubeadm and Ansible |
| D3 | Cluster CIDRs | Explicit pod and service CIDRs that do not overlap `10.77.0.0/24`, `10.78.0.0/24`, `172.16.212.0/23`, `172.16.214.0/23`, `172.17.0.0/16` to `172.21.0.0/16`, `192.168.122.0/24` | Cilium's default pool is large and can overlap; choose and record before `kubeadm init` |
| D4 | MetalLB pool | A range inside `kg-isolated-network` above the DHCP pool, for example `10.77.0.200-10.77.0.220` | Reachable from the host on the bridge `kg-isolated-br` |
| D5 | Internet during build | Nodes get a second interface on `kg-internet-access-network` only while packages and images are fetched, then it is detached ([ADR-001](../adr/ADR-001-lab-network-isolation.md)). Cilium and kubelet are pinned to the `kg-isolated-network` interface | Keeps the attack network isolated and the build repeatable |
| D6 | Image supply | Pull from public registries during the build window; evaluate preloading or a local registry if pulls are slow or rate-limited | Offline operation after detaching `kg-internet-access-network` |
| D7 | Ingress | ingress-nginx or Cilium Gateway API, decided by ADR in P1-U12 | Plan allows either |
| D8 | Versions | Pin Kubernetes, containerd, Cilium, MetalLB and the monitoring stack in one `versions` file, checked against each project's release page when P1-U2 starts | Reproducibility; versions are not fixed in this draft |
| D9 | Ansible inventory | Static inventory generated from the node address table | Simple and repeatable |

## Units

| Unit | Description | Acceptance check | Branch | Status |
|---|---|---|---|---|
| P1-U1 | Three VMs from cloud-init (infra definitions) | `make vms` creates 3 reachable VMs | `feat/p1-nodes` | [x] |
| P1-U2 | Ansible role `common` (swap off, kernel modules, sysctl) | Idempotent re-run reports no changes | `feat/p1-nodes` | [x] |
| P1-U3 | Ansible role `containerd` | `crictl info` OK on all nodes | `feat/p1-nodes` | [x] |
| P1-U4 | Ansible roles kubeadm init and join | 3 nodes join, API reachable | `feat/p1-nodes` | [x] |
| P1-U5 | Cilium with kube-proxy replacement, Hubble relay and UI | `cilium status` healthy, flows visible | `feat/p1-cluster-networking` | [ ] |
| P1-U6 | MetalLB (L2 pool), ingress or Gateway API, local-path storage | LoadBalancer IP assigned, PVC binds | `feat/p1-cluster-networking` | [ ] |
| P1-U7 | kube-prometheus-stack with short retention | Grafana dashboards load, RAM within budget | `feat/p1-apps-monitoring` | [ ] |
| P1-U8 | Sample app via MetalLB and ingress, flows seen in Hubble | Request from host succeeds, flow appears | `feat/p1-apps-monitoring` | [ ] |
| P1-U9 | etcd snapshot and restore drill | Restore tested, steps in runbook | `feat/p1-cluster-drills` | [ ] |
| P1-U10 | Node drain, node failure and rejoin drills | Cluster recovers, steps in runbook | `feat/p1-cluster-drills` | [ ] |
| P1-U11 | `make up`, `make down`, `make reset`, `make cluster` | Clean VMs to Ready cluster with one command | `feat/p1-cluster-automation` | [ ] |
| P1-U12 | ADRs: CNI, load balancer, ingress, storage | 4 ADRs committed | `feat/p1-cluster-networking` | [ ] |
| P1-U13 | Rebuild time measured | Documented, target under 40 minutes | `feat/p1-cluster-automation` | [ ] |
| P1-U14 | Phase 2 spec | `docs/specs/P2-hardening.md` approved | `docs/p1-p2-spec` | [ ] |

## Branches

Related units share one feature branch. Each branch is cut from `main`, merged into `dev` and checked there, then merged into `main`. Units inside a branch are worked one at a time, each ending at its acceptance check with its own commit, evidence under `docs/reports/` and a unit-details entry in this spec. No branch is deleted after merging.

| Branch | Units | Done when |
|---|---|---|
| `feat/p1-nodes` | P1-U1 to U4 | 3 nodes Ready, API reachable, `common` role idempotent |
| `feat/p1-cluster-networking` | P1-U5, U6, U12 | Hubble healthy, LoadBalancer IP assigned, PVC binds, 4 ADRs committed |
| `feat/p1-apps-monitoring` | P1-U7, U8 | Dashboards load, request from host succeeds, flow visible in Hubble |
| `feat/p1-cluster-drills` | P1-U9, U10 | etcd restore tested, node drills done, both runbooks written |
| `feat/p1-cluster-automation` | P1-U11, U13 | `make cluster` from clean VMs, rebuild time documented |
| `docs/p1-p2-spec` | P1-U14 and the Phase 1 retrospective | Phase 2 spec approved |

If a unit fails its check on `dev`, it is fixed on its branch and merged into `dev` again; the other branches are not blocked.

## Unit plan

Dependencies, deliverables and division of work. Core cluster setup is written by the researcher first, as agreed in CLAUDE.md; the assistant helps with scripts, tests and documentation and reviews diffs.

| Unit | Depends on | Main artifacts | Researcher writes | Assistant helps with |
|---|---|---|---|---|
| P1-U1 | P0-U6 | `infra/libvirt/` node definitions, per-node cloud-init, DHCP reservations, Makefile `vms` | Node layout and sizing | Clone and seed scripts, tests |
| P1-U2 | U1 | `infra/ansible/roles/common`, inventory, `versions` file | Kernel modules and sysctl choices | Role skeleton, idempotence test |
| P1-U3 | U2 | `roles/containerd` | Runtime configuration | Role, `crictl` check |
| P1-U4 | U3 | `roles/kubeadm_init`, `roles/kubeadm_join`, kubeconfig handling (project kubeconfig only) | kubeadm configuration | Role plumbing, join test |
| P1-U5 | U4, D3 | `k8s/cilium/values.yaml`, install target | Cilium values and interface pinning | Install automation, `cilium status` check |
| P1-U6 | U5, D4 | `k8s/metallb/`, ingress values, storage class | Address pool, ingress choice | Manifests, PVC and LoadBalancer tests |
| P1-U7 | U6 | `k8s/monitoring/values.yaml` | Retention and resource limits | Helm automation, dashboard check |
| P1-U8 | U6, U5 | `k8s/sample-app/` | App choice | Manifests, request test |
| P1-U9 | U4 | `docs/runbooks/etcd-restore.md`, snapshot script | Restore procedure | Script, runbook draft |
| P1-U10 | U4 | `docs/runbooks/node-failure.md` | Drill execution | Checklists, runbook draft |
| P1-U11 | U1 to U8 | Makefile targets `up`, `down`, `reset`, `cluster` | Target semantics | Make glue, error handling |
| P1-U12 | U5, U6 | `docs/adr/ADR-00x-*.md` (CNI, load balancer, ingress, storage) | Decisions | ADR drafts from the template |
| P1-U13 | U11 | `docs/reports/P1-rebuild-time.md` | The measured runs | Report layout |
| P1-U14 | U1 to U13 | `docs/specs/P2-hardening.md` | Hardening priorities | Draft from the master plan |

Work order: U1 to U4, then U5, U6 and U8 together, then U7, U9 and U10, then U11, U12 and U13, then U14. Each unit ends at its acceptance check, with evidence under `docs/reports/` and a unit-details entry in this spec.

## Unit details

One entry per finished unit: objective, rationale, deliverables, implementation, verification and status. The status column of the unit table is ticked when the branch is merged.

### P1-U1: Cluster node VMs

**Objective.** Create the three cluster nodes as virtual machines that can be rebuilt from the repository.

**Rationale.** Every later unit (node preparation, containerd, kubeadm, Cilium) runs on these nodes. Fixed names and addresses, a known size and a clean restore point make those units repeatable.

**Deliverables.**
- `infra/libvirt/nodes.conf`: the node list (name, role, address, MACs, vCPUs, memory, disk).
- `infra/libvirt/build-nodes.sh`: `create`, `status`, `test`, `isolate`, `snapshot`, `restore`, `destroy`, with Makefile targets `vms`, `vms-status`, `vms-test`, `vms-isolate`, `vms-snapshot`, `vms-restore`, `vms-destroy`.
- `infra/cloud-init/node-user-data.tpl` and `node-network-config.tpl`.
- DHCP reservations for the three nodes in `infra/libvirt/kg-isolated-network.xml`.
- [docs/reports/P1-U1-vms-evidence.md](../reports/P1-U1-vms-evidence.md) and [docs/naming.md](../naming.md).

**Implementation.** Each node disk is a copy of `kg-template-disk.qcow2` grown to 20 GiB. Each node gets its own cloud-init seed with its hostname, the lab key, a new machine-id and a two-interface network configuration: `isolated0` (permanent, fixed address through a DHCP reservation) and `internet0` (build window only, lower route metric). Sizing starts minimal (decision D1): 2 vCPU and 2 GiB per node.

**Verification.** `make vms` creates three nodes reachable over SSH; `make vms-test` passes 21 checks (hostname, vCPUs, memory, disk size, kernel BTF, unique machine-ids, node-to-node reachability); `make vms-isolate` shows the nodes cannot reach the LAN gateway or the internet once `internet0` is detached; `make vms-restore` returns them to their clean snapshots. The masquerade check, which needs `sudo`, was run from a terminal and passes.

**Status.** Done. Branch `feat/p1-nodes`.

### P1-U2: Ansible role `common`

**Objective.** Prepare every node with the operating-system settings Kubernetes needs, in a way that can be repeated without side effects.

**Rationale.** kubelet and kubeadm refuse to run, or run unreliably, without swap off, the container and bridge kernel modules, and the forwarding settings. A role with checks at its end turns "the node is ready" into something a command can prove.

**Deliverables.**
- `infra/ansible/`: `ansible.cfg`, the inventory generator `gen-inventory.sh` (inventory from `nodes.conf`), `site.yml`, `group_vars/all.yml`, `roles/common`, `test-idempotence.sh`, and `requirements.txt` (`ansible-core==2.21.5`).
- `infra/versions.env`: the version-pin file, started with the Ansible version.
- Makefile targets `ansible-setup`, `ansible-inventory`, `ansible-apply`, `ansible-test`.
- [docs/reports/P1-U2-common-evidence.md](../reports/P1-U2-common-evidence.md).

**Implementation.** The role turns swap off and comments the swap line in `/etc/fstab`, loads `overlay` and `br_netfilter` now and on boot, sets `net.ipv4.ip_forward` and the two bridge-netfilter parameters, and writes the node names into `/etc/hosts`. It uses only modules built into Ansible, so no extra collections are needed. Its last tasks fail the run if a node is not in the intended state. Ansible runs from the project virtual environment `.venv`, which is not stored in git.

**Verification.** The first run changes 5 settings per node; the second run reports `changed=0` and `failed=0` on all three nodes; a direct check on a rebooted node shows the settings are intact. One defect was found by the reboot test and fixed (cloud-init rewrote `/etc/hosts` on every boot).

**Status.** Done. Branch `feat/p1-nodes`.

### P1-U3: Ansible role `containerd`

**Objective.** Install and configure the container runtime on every node, from pinned and verified files.

**Rationale.** kubelet talks to a container runtime through CRI. The runtime version must be supported by the Kubernetes version chosen for P1-U4, and pinned so rebuilds give the same result.

**Deliverables.**
- `infra/ansible/roles/containerd`: tasks, handlers and two templates (`config.toml.j2`, `containerd.service.j2`).
- Pins and SHA256 hashes in `infra/ansible/group_vars/all.yml`; versions recorded in `infra/versions.env`.
- [docs/reports/P1-U3-containerd-evidence.md](../reports/P1-U3-containerd-evidence.md).

**Implementation.** containerd 2.3.6 (the LTS line, supported until April 2028), runc 1.5.2 and `crictl` 1.37.0 are downloaded from the project release pages and checked against pinned hashes. The role writes a minimal containerd configuration (config version 4, systemd cgroup driver), a systemd unit from a template, and `/etc/crictl.yaml`. It creates `/opt/cni/bin` and `/etc/cni/net.d` but installs no CNI plugin, because Cilium provides pod networking in P1-U5. Ubuntu's own `containerd` package was not used: it is version 2.2.1, which Kubernetes 1.37 does not support and which reaches end of life on 2026-11-06. The role ends with checks (versions, cgroup driver, `crictl info` RuntimeReady).

**Verification.** `crictl info` reports RuntimeReady on all three nodes; the second Ansible run reports `changed=0`; a pulled image can be removed and pulled again; containerd is active after a reboot. `NetworkReady` is false until Cilium is installed, as expected. Two defects were found and fixed (a `pipefail` check, an outdated config version).

**Status.** Done. Branch `feat/p1-nodes`.

### P1-U4: kubeadm init and join

**Objective.** Create the Kubernetes control plane on `kg-control-1` and join both workers, reproducibly.

**Rationale.** This is the base of the cluster. Everything later (Cilium, ingress, monitoring, hardening, attacks) runs on it, so its settings must be explicit and repeatable.

**Deliverables.**
- Roles `kubernetes_packages`, `kubeadm_init` and `kubeadm_join`, and three more plays in `infra/ansible/site.yml` (control plane, join, cluster check).
- Pins and addressing in `infra/ansible/group_vars/all.yml`: Kubernetes 1.37.1, the repository key fingerprint, pod and service CIDRs.
- Makefile target `kubectl` (project kubeconfig only).
- [docs/reports/P1-U4-kubeadm-evidence.md](../reports/P1-U4-kubeadm-evidence.md) and the runbook [docs/runbooks/lab-operations.md](../runbooks/lab-operations.md) (how to operate every layer of the lab, inspect and rebuild the cluster, and the rules for the project kubeconfig).

**Implementation.** `kubelet` and `kubeadm` (and `kubectl` on the control node) are installed at the pinned version from the official apt repository after the signing key is checked against a pinned fingerprint, then held. Each kubelet starts with `--node-ip` set to the node's isolated address, so the cluster never uses the temporary internet interface. `kubeadm init` runs from a configuration file (API `v1beta4`) only when `admin.conf` does not exist; workers join with a short-lived token created on the control node only when `kubelet.conf` does not exist, and the token is not logged. The admin kubeconfig is fetched to `~/.kube/kubeguard.kubeconfig` (mode 0600, outside the repository). `kube-proxy` is skipped because Cilium replaces it.

**Verification.** `kubectl get nodes` from the host shows three nodes with their isolated addresses and version v1.37.1; the API answers `ok` on `/readyz`; the control-plane pods are `Running`; `kube-proxy` does not exist; the second Ansible run reports `changed=0`. Nodes are `NotReady` and CoreDNS is `Pending` until the pod network exists (P1-U5), as expected.

**Status.** Done. Branch `feat/p1-nodes`.

## Risks

- **RAM and disk.** The host is shared and has limited free memory. Mitigation: start with minimal sizes (D1), short Prometheus retention, thin disks, and measure idle use before scaling.
- **Two networks.** Build-time internet (`kg-internet-access-network`) and the isolated `kg-isolated-network` must not blur. Mitigation: D5, the isolation test from P0-U5 re-run after the build, and the interface check in P1-U5.
- **Image pulls.** Public registries may rate-limit or be slow. Mitigation: D6.
- **Kernel features.** eBPF-based Cilium and later phases need a guest kernel with BTF. Mitigation: check `/sys/kernel/btf/vmlinux` on a node in P1-U1.
- **Rebuild time.** Target is under 40 minutes. Mitigation: cache images, keep the base image current, measure in U13 and shorten the slowest step.
- **Version drift.** Mitigation: D8.
- **Snapshots.** Every hardening change and attack run needs a VM snapshot first (lab rule). Mitigation: a `make snapshot` target added in U11.

## Gate

No gate closes Phase 1. Gate G1 follows Phase 2. Pass condition for the phase: from clean VMs, `make cluster` produces a Ready cluster with Hubble flows visible, the etcd restore has been tested, and the rebuild time is documented.

## Amendments

Changes to the approved plan during Phase 1. One line each: date, decision number, change, reason.

2026-10-09 | workflow | The 14 units are grouped into six branches (see Branches and the Branch column) | Fewer branches, same acceptance checks per unit
2026-10-10 | workflow | The networking branch is named `feat/p1-cluster-networking` (was `feat/p1-networking`) | The name says what the branch builds: the cluster networking
2026-10-10 | workflow | The drills and automation branches are named `feat/p1-cluster-drills` (was `feat/p1-drills`) and `feat/p1-cluster-automation` (was `feat/p1-automation`) | The names say that both work on the whole cluster

## Retrospective

(Filled at phase exit.)
