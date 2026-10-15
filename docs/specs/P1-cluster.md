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

## Flow of Phase 1

What gets built, and why in this order. Units marked (done) are finished; the rest are planned.

```
P1-U1  node VMs from the template (done) ........... machines exist, fixed addresses
  │
P1-U2  Ansible role common (done) .................. swap off, kernel modules, sysctl
  │
P1-U3  containerd (done) ........................... a container runtime on every node
  │
P1-U4  kubeadm init and join (done) ................ control plane up, workers joined, nodes NotReady
  │
P1-U5  Cilium + Hubble ............................. pod network, replaces kube-proxy: nodes Ready
  │
P1-U6  MetalLB, ingress or Gateway, storage ........ LoadBalancer IPs, a front door, disk for pods
P1-U12 ADRs: CNI, load balancer, ingress, storage .. written as each choice is built
  │
P1-U7  Prometheus and Grafana ...................... baseline monitoring (RAM gets tight here)
P1-U8  sample app ................................. reached from the host; its flow appears in Hubble
  │
P1-U9  etcd snapshot and restore ................... the cluster state can be recovered
P1-U10 node drain, failure and rejoin .............. the cluster survives losing a node
  │
P1-U11 make up / down / reset / cluster ............ one command from clean VMs to a Ready cluster
P1-U13 rebuild time ................................ measured, target under 40 minutes
  │
P1-U14 Phase 2 spec ................................ hardening plan, approved before it starts
```

Why this order:
1. **Machines before software (U1 to U3).** Kubernetes needs identical, prepared nodes with a runtime. Doing this with Ansible first means every later step can be repeated on a rebuilt node.
2. **The control plane before the network (U4 before U5).** `kubeadm` creates the API server and joins the workers. Nodes stay `NotReady` until a pod network exists, which is why Cilium comes next and kube-proxy was skipped at init.
3. **The pod network before anything that serves traffic (U5 before U6).** MetalLB, ingress and storage all rely on pods being able to talk to each other and on Services working.
4. **Monitoring and the sample app after the network (U7, U8).** Both need a working cluster, and U8 proves U5 and U6 together: a request from the host passes MetalLB and ingress, and Hubble shows the flow.
5. **Drills after the cluster has something worth recovering (U9, U10).** The etcd restore and node-failure drills are only meaningful once the cluster holds real state.
6. **Automation last (U11, U13).** Wrapping the steps in `make` is only reliable once each step works by hand, and the rebuild time can only be measured on the complete chain.
7. **The Phase 2 spec at the end (U14).** Hardening is planned from what Phase 1 actually produced.

### In AWS terms

| In this lab | Closest AWS idea |
|---|---|
| libvirt and KVM on the host | The hypervisor under EC2 |
| `kg-isolated-network` (no internet) | A private subnet with no route to an internet or NAT gateway |
| `kg-internet-access-network` (build time only) | A subnet reached through a NAT gateway, attached only while installing |
| `kg-template-vm` and its snapshot | An AMI and an EBS snapshot |
| cloud-init seed | EC2 user data |
| Node VMs `kg-control-1`, `kg-worker-1`, `kg-worker-2` | EC2 instances: one for the control plane, two as a node group |
| DHCP reservations (fixed node addresses) | Fixed private IPs on network interfaces |
| Ansible roles | Systems Manager State Manager, or any configuration management |
| containerd | The container runtime on EKS worker nodes |
| `kubeadm init` and `join` | What EKS does for you when it creates a managed control plane and joins nodes |
| The project kubeconfig | The file `aws eks update-kubeconfig` writes |
| Cilium | VPC CNI plus kube-proxy |
| Hubble | VPC Flow Logs, but pod-aware and with policy verdicts |
| MetalLB | The network load balancer that Kubernetes creates for a `LoadBalancer` Service |
| Ingress or Gateway API | An application load balancer with the AWS Load Balancer Controller |
| local-path storage | EBS volumes through the EBS CSI driver |
| Prometheus and Grafana | CloudWatch Container Insights, or Managed Prometheus and Managed Grafana |
| etcd snapshot and restore | Something EKS does for you; here you do it yourself |
| Node drain and failure drills | Replacing instances in a managed node group |
| `make cluster` | Terraform or eksctl: one command that builds the environment |

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
| P1-U5 | Cilium with kube-proxy replacement, Hubble relay and UI | `cilium status` healthy, flows visible | `feat/p1-cluster-networking` | [x] |
| P1-U6 | Cilium LB IPAM with L2 announcements, Cilium Gateway API, local-path storage | LoadBalancer IP assigned, PVC binds | `feat/p1-cluster-networking` | [x] |
| P1-U7 | kube-prometheus-stack with short retention | Grafana dashboards load, RAM within budget | `feat/p1-cluster-monitoring-apps` | [x] |
| P1-U8 | Sample app via the load balancer and Gateway, flows seen in Hubble | Request from host succeeds, flow appears | `feat/p1-cluster-monitoring-apps` | [x] |
| P1-U9 | etcd snapshot and restore drill | Restore tested, steps in runbook | `feat/p1-cluster-drills` | [x] |
| P1-U10 | Node drain, node failure and rejoin drills | Cluster recovers, steps in runbook | `feat/p1-cluster-drills` | [x] |
| P1-U11 | `make up`, `make down`, `make reset`, `make cluster` | Clean VMs to Ready cluster with one command | `feat/p1-cluster-automation` | [x] |
| P1-U12 | ADRs: CNI, load balancer, ingress, storage | 4 ADRs committed | `feat/p1-cluster-networking` | [x] |
| P1-U13 | Rebuild time measured | Documented, target under 40 minutes | `feat/p1-cluster-automation` | [x] |
| P1-U14 | Phase 2 spec | `docs/specs/P2-hardening.md` approved | `docs/p1-p2-spec` | [ ] |

## Branches

Related units share one feature branch. Each branch is cut from `main`, merged into `dev` and checked there, then merged into `main`. Units inside a branch are worked one at a time, each ending at its acceptance check with its own commit, evidence under `docs/reports/` and a unit-details entry in this spec. No branch is deleted after merging.

| Branch | Units | Done when |
|---|---|---|
| `feat/p1-nodes` | P1-U1 to U4 | 3 nodes Ready, API reachable, `common` role idempotent |
| `feat/p1-cluster-networking` | P1-U5, U6, U12 | Hubble healthy, LoadBalancer IP assigned, PVC binds, 4 ADRs committed |
| `feat/p1-cluster-monitoring-apps` | P1-U7, U8 | Dashboards load, request from host succeeds, flow visible in Hubble |
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
| P1-U6 | U5, D4 | `k8s/cilium/lb-pool.yaml`, `l2-policy.yaml`, Gateway API CRDs, storage class | Address pool, ingress choice | Manifests, PVC and LoadBalancer tests |
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

**Implementation.** containerd 2.3.6 (the LTS line, supported until April 2028), runc 1.5.2 and `crictl` 1.36.0 are downloaded from the project release pages and checked against pinned hashes. The role writes a minimal containerd configuration (config version 4, systemd cgroup driver), a systemd unit from a template, and `/etc/crictl.yaml`. It creates `/opt/cni/bin` and `/etc/cni/net.d` but installs no CNI plugin, because Cilium provides pod networking in P1-U5. Ubuntu's own `containerd` package was not used: it is version 2.2.1, which Kubernetes 1.37 does not support and which reaches end of life on 2026-11-06. The role ends with checks (versions, cgroup driver, `crictl info` RuntimeReady).

**Verification.** `crictl info` reports RuntimeReady on all three nodes; the second Ansible run reports `changed=0`; a pulled image can be removed and pulled again; containerd is active after a reboot. `NetworkReady` is false until Cilium is installed, as expected. Two defects were found and fixed (a `pipefail` check, an outdated config version).

**Status.** Done. Branch `feat/p1-nodes`.

### P1-U4: kubeadm init and join

**Objective.** Create the Kubernetes control plane on `kg-control-1` and join both workers, reproducibly.

**Rationale.** This is the base of the cluster. Everything later (Cilium, ingress, monitoring, hardening, attacks) runs on it, so its settings must be explicit and repeatable.

**Deliverables.**
- Roles `kubernetes_packages`, `kubeadm_init` and `kubeadm_join`, and three more plays in `infra/ansible/site.yml` (control plane, join, cluster check).
- Pins and addressing in `infra/ansible/group_vars/all.yml`: Kubernetes 1.36.5, the repository key fingerprint, pod and service CIDRs.
- Makefile target `kubectl` (project kubeconfig only).
- [docs/reports/P1-U4-kubeadm-evidence.md](../reports/P1-U4-kubeadm-evidence.md) and the runbook [docs/runbooks/lab-operations.md](../runbooks/lab-operations.md) (how to operate every layer of the lab, inspect and rebuild the cluster, and the rules for the project kubeconfig).

**Implementation.** `kubelet` and `kubeadm` (and `kubectl` on the control node) are installed at the pinned version from the official apt repository after the signing key is checked against a pinned fingerprint, then held. Each kubelet starts with `--node-ip` set to the node's isolated address, so the cluster never uses the temporary internet interface. `kubeadm init` runs from a configuration file (API `v1beta4`) only when `admin.conf` does not exist; workers join with a short-lived token created on the control node only when `kubelet.conf` does not exist, and the token is not logged. The admin kubeconfig is fetched to `~/.kube/kubeguard.kubeconfig` (mode 0600, outside the repository). `kube-proxy` is skipped because Cilium replaces it.

**Verification.** `kubectl get nodes` from the host shows three nodes with their isolated addresses and version v1.36.5; the API answers `ok` on `/readyz`; the control-plane pods are `Running`; `kube-proxy` does not exist; the second Ansible run reports `changed=0`. Nodes are `NotReady` and CoreDNS is `Pending` until the pod network exists (P1-U5), as expected.

**Status.** Done. Branch `feat/p1-nodes`.

### P1-U5: Cilium and Hubble

**Objective.** Give the cluster a pod network that also replaces kube-proxy, and make traffic visible.

**Rationale.** Nodes stay `NotReady` until a CNI exists. Cilium implements pod networking and Services with eBPF, so it replaces kube-proxy, and Hubble shows which pod talks to which. Both are needed by the load balancer, ingress, monitoring and the detection work in later phases.

**Deliverables.**
- `k8s/cilium/values.yaml`, Makefile targets `cilium-install`, `cilium-status`, `cilium-uninstall`, `hubble-ui`, and the versions in `infra/versions.env`.
- [docs/reports/P1-U5-cilium-evidence.md](../reports/P1-U5-cilium-evidence.md).

**Implementation.** Helm 4.3.0 installs the pinned chart `cilium/cilium` 1.20.2 from the host with the project kubeconfig. Cilium runs with `kubeProxyReplacement: true` (told the real API address `10.77.0.10:6443`), uses the pod ranges kubeadm allocated (`ipam.mode: kubernetes`), attaches only to `isolated0`, tunnels between nodes with VXLAN, and runs Hubble relay and UI with a single operator. Kubernetes was moved to 1.36.5 before this unit because Cilium 1.20 lists Kubernetes 1.33 to 1.36 only (see the amendments).

**Verification.** `cilium status` reports Cilium, the operator, Envoy and Hubble Relay `OK`; all three nodes are `Ready` and CoreDNS runs; a request from a client pod to a test Service succeeds with no kube-proxy in the cluster; Hubble shows the flows (DNS and TCP) with verdict `FORWARDED` from all three nodes.

**Status.** Done. Branch `feat/p1-cluster-networking`.

### P1-U6: Load balancer, Gateway API and storage

**Objective.** Let workloads be reached from outside the cluster at layer 4 (address and port) and layer 7 (HTTP host and path), and give them persistent volumes.

**Rationale.** A bare-metal cluster has no cloud load balancer, so a Service of type `LoadBalancer` stays without an address and no ingress exists. Cilium already runs as the pod network (P1-U5); using it for the load balancer and the ingress avoids a second component (MetalLB) and keeps one data path that Hubble can observe. Layer 4 is required because several attack scenarios use non-HTTP traffic (scans, DNS tunnelling, exfiltration); layer 7 is required for realistic web workloads and HTTP-level visibility. ingress-nginx was not chosen because it is retired. Storage uses local-path, which fits a lab with local disks. The choices are recorded as ADRs in P1-U12.

**Deliverables.**
- `k8s/cilium/values.yaml` (L2 announcements, external IPs, client rate limit, Gateway API), `k8s/cilium/lb-pool.yaml`, `k8s/cilium/l2-policy.yaml`.
- Makefile targets `gateway-api-crds`, `cilium-lb`, `storage-install`, `net-test-u6`; versions `GATEWAY_API` and `LOCAL_PATH` in `infra/versions.env`.
- Acceptance checks `k8s/tests/lb-test.yaml`, `gateway-test.yaml`, `pvc-test.yaml`.
- Makefile target `cilium-restart` (added after a finding during the run).
- [docs/reports/P1-U6-lb-gateway-storage-evidence.md](../reports/P1-U6-lb-gateway-storage-evidence.md).

**Design.** The four Cilium files answer four questions:

| Question | File | AWS counterpart |
|---|---|---|
| Which addresses may a LoadBalancer use? | `lb-pool.yaml` | Address space an NLB draws from |
| Who announces the address on the network? | `l2-policy.yaml` | The AWS network layer that routes NLB addresses |
| Which Cilium features run? | `values.yaml` | The load balancer controller and the NLB and ALB products |
| How is it proven to work? | `k8s/tests/` | Smoke tests after a deploy |

- `values.yaml`: `l2announcements.enabled` lets a node answer ARP for a Service address (this replaces the MetalLB speaker); `externalIPs.enabled` lets the eBPF code handle traffic to such addresses; `k8sClientRateLimit` is raised because L2 announcements keep one lease per Service; `gatewayAPI.enabled` starts the Gateway controller and registers the `cilium` GatewayClass, and needs the Gateway API CRDs installed first. LB IPAM (the address assignment) is on by default and idle until a pool exists.
- `lb-pool.yaml`: `10.77.0.200` to `10.77.0.220`, above the DHCP range (.100 to .199) and the node addresses (.10 to .12). LB IPAM writes the next free address into the `EXTERNAL-IP` of each `LoadBalancer` Service.
- `l2-policy.yaml`: announces LoadBalancer addresses on `isolated0` only, from worker nodes only. For each Service one eligible node holds a Kubernetes lease and answers ARP; another node takes the lease if it fails.
- Limits: L2 announcement works only inside one network segment (true for `kg-isolated-network`), and one node receives all traffic for an address before eBPF spreads it to the pods. This is sufficient for a lab and is not a multi-node load balancer.

**Network flow, layer 4 (`lb-test` Service).**

```
client (10.77.0.x)
  | 1. ARP: "who has 10.77.0.200?"
  v
kg-isolated-network bridge --> kg-worker-1 answers with its MAC (it holds the lease, per l2-policy.yaml)
  | 2. TCP to 10.77.0.200:80 arrives on worker-1 isolated0
  v
Cilium eBPF on isolated0 (replaces kube-proxy)
  | 3. matches the LoadBalancer Service and picks a backend pod (any node; VXLAN tunnel if remote)
  v
pod lb-test (10.244.x.x)
  | 4. the reply returns the same way (eBPF keeps the connection state)
  v
client
```

No HTTP is read. Hubble shows TCP flows between addresses.

**Network flow, layer 7 (`gw-test` Gateway and HTTPRoute).**

```
client --> 10.77.0.201:80   (pool address given to the Service Cilium creates for the Gateway,
  |                          announced by L2 as above)
  v
worker-N: eBPF redirects the traffic to Cilium's embedded Envoy (layer 7 proxy)
  | Envoy reads the HTTP request (host, path, headers)
  | HTTPRoute rule: path prefix "/" --> Service lb-test:80
  v
Envoy opens a new connection to an lb-test pod --> response --> Envoy --> client
```

The Gateway is the listener (port 80, HTTP), the HTTPRoute is the routing table. Envoy runs inside the Cilium agent, so no extra proxy pods are needed. The HTTP request is terminated and re-created, which is why Hubble can show HTTP-level data.

**Storage flow (`pvc-test`).**

```
PVC pvc-test --> default StorageClass local-path --> provisioner creates a folder on the node disk
pod pvc-test scheduled on a node --> mounts the folder at /data --> writes "ok"
```

The data lives on one node, so the pod is tied to that node (comparable to EBS, but local).

**Implementation.** Order of work: install the Gateway API CRDs (pinned `standard-install.yaml`), upgrade the Cilium release with the new values, apply the pool and policy, install local-path-provisioner and mark its StorageClass as default. Helm updates the Cilium ConfigMap but does not restart the pods, so `make cilium-restart` follows every values change (without it, L2 announcements and the Gateway controller stay inactive). Image pulls need the internet window (`make vms-attach-internet`). The window stays open through the remaining build units and is closed (`make vms-isolate`) at the end of Phase 1 and before any attack run.

**Verification.** `net-test-u6` must show: `lb-test` receiving an address from `10.77.0.200-220` and answering from a host on the isolated network; the Gateway `gw-test` programmed with an address and `HTTPRoute` accepted, and a request through it reaching `lb-test`; `pvc-test` bound and the pod `Ready`. `cilium status` stays healthy.

**Status.** Done. Branch `feat/p1-cluster-networking`. The nodes are still in the build window; isolation is verified at the end of Phase 1.

### P1-U7: Monitoring

**Objective.** Run Prometheus and Grafana so cluster and node health can be observed, and size the nodes to carry them.

**Rationale.** Later phases measure overhead (RQ2) and need a baseline of node and cluster behaviour. The nodes started at 2 GiB (D1) and the control plane had 803 MiB available, so the memory was raised first, as D1 allows when a unit needs it.

**Deliverables.**
- `k8s/monitoring/values.yaml` and `test.sh`, Makefile targets `monitoring-secret`, `monitoring-install`, `monitoring-status`, `monitoring-uninstall`, `grafana-password`, `grafana-ui`, `net-test-u7`, and `vms-resize`; the chart version in `infra/versions.env`; the new memory sizes in `infra/libvirt/nodes.conf` and the `resize` command in `infra/libvirt/build-nodes.sh`.
- [docs/reports/P1-U7-monitoring-evidence.md](../reports/P1-U7-monitoring-evidence.md).

**Implementation.** `make vms-resize` set the memory to 3 GiB (control plane) and 5 GiB (workers), one node at a time. `kube-prometheus-stack` 92.6.0 is installed with Helm from the host with short retention (3 days, 4 GB), a 5 GiB `local-path` volume, resource limits on every component (the Grafana limit was raised to 768 Mi after an out-of-memory kill during dashboard browsing) and no Alertmanager. The Grafana admin password lives only in a Secret created in the cluster. Targets that kubeadm does not expose (etcd, scheduler, controller manager) and kube-proxy are disabled.

**Verification.** All pods `Running` and the volume `Bound`; Prometheus reports 20 targets with none down and metrics from all three nodes; Grafana's health endpoint reports the database `ok` and 24 dashboards are provisioned; the researcher opened Grafana in the browser through a port-forward.

**Status.** Done. Branch `feat/p1-cluster-monitoring-apps`.

### P1-U8: Sample application

**Objective.** Run a small application behind the Gateway and show its flows in Hubble.

**Rationale.** It exercises the whole entry path built in P1-U5 and P1-U6 (address pool, L2 announcement, Envoy, pod network) with a real two-tier request, and shows that Hubble sees both the HTTP request and the pod-to-pod connection. The larger Online Boutique application is planned for P3-U1 and does not fit the 2 GiB nodes now.

**Deliverables.**
- `k8s/sample-app/` (namespace, backend, frontend, Gateway and HTTPRoute, `test.sh`), Makefile targets `sample-app-install`, `sample-app-remove`, `net-test-u8`.
- [docs/reports/P1-U8-sample-app-evidence.md](../reports/P1-U8-sample-app-evidence.md).

**Implementation.** Two nginx deployments (`nginx:1.27-alpine`, 16 Mi memory request each) in namespace `sample`. The frontend answers `/` and passes `/api` to the backend Service; a Gateway `sample-gw` with an HTTPRoute exposes the frontend on a pool address. `test.sh` reads the Gateway address, requests both paths from the host (with a retry, see the evidence) and prints Hubble flows from every Cilium agent.

**Verification.** `/` returns `frontend ok` and `/api` returns `backend ok` from the host; Hubble shows `http-request` and `http-response` records and the frontend to backend TCP connection with verdict `FORWARDED`.

**Status.** Done. Branch `feat/p1-cluster-monitoring-apps`.

### P1-U9: etcd snapshot and restore drill

**Objective.** Show that the cluster state can be recovered from an etcd snapshot, and document the procedure.

**Rationale.** The cluster has one control-plane node and one etcd member, so a snapshot is the only way back from lost or damaged cluster state. Hardening in Phase 2 changes the cluster in ways that may need undoing. A recovery path that was never tested is not a recovery path.

**Deliverables.**
- `infra/drills/etcd.sh` (`snapshot`, `restore`, `drill`), Makefile targets `etcd-snapshot`, `etcd-restore`, `drill-etcd`; `docs/runbooks/etcd-restore.md`.
- [docs/reports/P1-U9-etcd-restore-evidence.md](../reports/P1-U9-etcd-restore-evidence.md).

**Implementation.** The etcd image already contains `etcdctl` and `etcdutl` (3.6.8), so all steps run through `crictl exec` on the node and nothing is installed. A snapshot is saved inside the etcd container, verified with `etcdutl snapshot status` and copied to the host outside the repository (it contains all Secrets). A restore builds the new data directory while etcd still runs, stops etcd and the API server by moving their static pod manifests away, swaps the data directories (keeping the old one) and starts both again. The drill makes a visible change after the snapshot, restores, and checks that the earlier state is back.

**Verification.** A deleted ConfigMap returned and a ConfigMap created after the snapshot disappeared; all nodes `Ready`, `kube-system` pods `Running`. A VM snapshot was taken before the drill.

**Status.** Done. Branch `feat/p1-cluster-drills`.

### P1-U10: Node drain, failure and rejoin drills

**Objective.** Show that the cluster survives losing a worker, and document how to drain, recover and rejoin one.

**Rationale.** Hardening in Phase 2 and the attack runs in Phase 3 will disturb nodes. Knowing how the cluster behaves when a worker is drained, crashes or is replaced, and having tested steps for each, makes those phases safer. It is also the self-managed counterpart of replacing instances in a managed node group.

**Deliverables.**
- `infra/drills/node.sh` (`drain`, `fail`, `rejoin`), Makefile targets `drill-node-drain`, `drill-node-fail`, `drill-node-rejoin`; `docs/runbooks/node-failure.md`.
- [docs/reports/P1-U10-node-drills-evidence.md](../reports/P1-U10-node-drills-evidence.md).

**Implementation.** Each drill checks that the cluster is healthy first and works on workers only. `drain` cordons and drains a worker and checks that no workload pod is left, then uncordons it. `fail` powers the VM off with a hard stop, waits for `NotReady` and for all Deployments to be available again on the other worker, then powers it on. `rejoin` drains the node, deletes it, resets it with `kubeadm reset`, reboots it, and joins it again with a new token and the node name and CRI socket used by the Ansible role. The script prints the times it measures.

**Verification.** Drain: Deployment pods moved and everything was `Running` again 32 s after the uncordon; Prometheus (local-path volume) stayed `Pending` while its node was drained. Failure: `NotReady` after 46 s, all Deployments available 490 s after the power-off, node `Ready` 22 s after power-on. Rejoin: node `Ready` 11 s after the join, Cilium agent ready after 26 s, address `10.77.0.12`, all pods `Running` after 31 s. A first rejoin run exceeded the script's wait because pods were placed on the node before its Cilium agent answered; the wait was extended and the cause recorded in the evidence.

**Status.** Done. Branch `feat/p1-cluster-drills`.

### P1-U11: Lifecycle commands

**Objective.** Take the lab from clean VMs to a verified cluster, and start, stop and reset it, each with one command.

**Rationale.** The cluster must be rebuildable without remembering a dozen steps: every later experiment may need a clean cluster, and a rebuild is the recovery of last resort. One script also keeps the order of the stages (networks, VMs, Kubernetes, Cilium, storage, monitoring, checks) in one place.

**Deliverables.**
- `infra/cluster.sh` and Makefile targets `up`, `down`, `reset`, `cluster`, `rebuild`; `docs/runbooks/rebuild.md`.
- [docs/reports/P1-U11-U13-rebuild-evidence.md](../reports/P1-U11-U13-rebuild-evidence.md).

**Implementation.** The script only chains the targets of the earlier units. `up` starts the networks and VMs and waits for the API and all nodes `Ready`; `down` shuts the VMs down gracefully; `reset` destroys the node VMs and creates clean ones from the template and refuses without `CONFIRM=yes`; `cluster` runs the stages in order and stops at the first failure, naming it; `rebuild` is `reset` plus `cluster`. Every stage is idempotent, so a failed run is repeated with `make cluster`. Each stage prints its duration and the log is written outside the repository.

**Verification.** `reset` without `CONFIRM` destroys nothing; `down` then `up` worked; `make cluster` on the running cluster passed all stages in 140 s without changes; `make rebuild CONFIRM=yes` rebuilt everything from clean VMs and passed all checks.

**Status.** Done. Branch `feat/p1-cluster-automation`.

### P1-U13: Rebuild time

**Objective.** Measure how long a rebuild from clean VMs takes and compare it with the 40 minute target.

**Rationale.** A rebuild that takes hours will not be used. The target keeps the lab cheap to reset between experiments, and the stage times show where the time goes.

**Deliverables.**
- Stage timing built into `infra/cluster.sh`; the measurement in [docs/reports/P1-U11-U13-rebuild-evidence.md](../reports/P1-U11-U13-rebuild-evidence.md).

**Implementation.** `make rebuild CONFIRM=yes` times each stage and the total, and prints `PASS` or `FAIL` against 2400 s.

**Verification.** One run from destroyed VMs to a verified cluster took 810 s (13 min 30 s): creating the VMs 140 s, Kubernetes with Ansible 231 s, Cilium and Hubble 180 s, monitoring 184 s, all other stages together 75 s. One measurement; it includes downloads on fresh nodes.

**Status.** Done. Branch `feat/p1-cluster-automation`.

### P1-U12: Architecture decision records

**Objective.** Record the four major networking and storage choices of Phase 1 as ADRs.

**Rationale.** The CNI, layer 4 load balancer, layer 7 entry and storage are choices that shape every later phase and could be questioned or changed. Each is written down with the options considered, the decision and its consequences, so the reasoning survives beyond the build.

**Deliverables.**
- [ADR-002](../adr/ADR-002-cni-cilium.md) (CNI and kube-proxy replacement), [ADR-003](../adr/ADR-003-load-balancer-cilium-l2.md) (layer 4 load balancer), [ADR-004](../adr/ADR-004-ingress-cilium-gateway-api.md) (layer 7 entry, resolves D7), [ADR-005](../adr/ADR-005-storage-local-path.md) (storage).

**Implementation.** Each ADR follows `docs/adr/_template.md` and cites the evidence report of the unit that verified it (P1-U5 and P1-U6). The load balancer decision replaces the MetalLB default of D4 and the plan's wording; see the amendments.

**Verification.** Four ADRs exist with status `accepted`, each with context, at least two options, a decision and consequences, and links to evidence that exists in `docs/reports/`.

**Status.** Done. Branch `feat/p1-cluster-networking`.

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
2026-10-10 | workflow | The monitoring and apps branch is named `feat/p1-cluster-monitoring-apps` (was `feat/p1-apps-monitoring`) | Consistent with the other cluster branches
2026-10-10 | D8 | Kubernetes pinned to 1.36.5 (was 1.37.1) and `crictl` to 1.36.0 (was 1.37.0); Helm 4.3.0 installed on the host (was 3.16.3); the cluster was rebuilt | Cilium 1.20 lists Kubernetes 1.33 to 1.36 only, 1.37 is not covered; Helm 4.3.x supports Kubernetes 1.34 to 1.37 and Helm 3.16 does not cover 1.36; containerd 2.3.6 supports 1.36
2026-10-14 | D4, D7 | Layer 4 load balancer is Cilium LB IPAM with L2 announcements (was MetalLB); layer 7 entry is Cilium Gateway API (was open between ingress-nginx and Gateway API); pool `10.77.0.200-220` unchanged | One component fewer, one observable data path; ingress-nginx is retired; see ADR-003 and ADR-004
2026-10-14 | D1 | Node memory raised to 3 GiB (control plane) and 5 GiB (workers), from 2 GiB each; the plan sizes (4, 8, 8 GiB) were not used | Control plane had 803 MiB available; 4/8/8 GiB would leave the 32 GB host with little free memory; sized as a start, to be tuned from measured use

## Retrospective

(Filled at phase exit.)
