# P0: Foundation (lab, repo, literature)

Status: draft, pending approval
Approved by / date:

## Objective

Prepare the repo and the isolated lab, and check that the research gap is real before building the cluster.

## Hypothesis and metrics

Hypothesis: there is room for a Kubernetes security dataset and benchmark that combines flow, runtime and audit signals, with benign changes (rollouts, autoscaling) included.
Metrics: 15+ papers in the literature matrix, and a written G0 decision.

## Scope

In scope: repo skeleton, assistant context files, templates, KVM/libvirt, isolated network, base VM image, literature matrix, RQ v0, P1 spec, cert decision.
Out of scope: Kubernetes install (P1), any attack work.

## Units

| Unit | Description | Acceptance check | Status |
|---|---|---|---|
| P0-U1 | Repo skeleton, README, Makefile | Tree exists, `make help` runs | [x] |
| P0-U2 | CLAUDE.md | Covers isolation, kubeconfig, snapshots, no-AI-numbers | [x] |
| P0-U3 | Spec, ADR, experiment-log templates | Templates present | [x] |
| P0-U4 | KVM/libvirt installed | `virt-host-validate` passes | [x] |
| P0-U5 | Isolated libvirt network | VMs reach each other, cannot reach home LAN (tested) | [~] |
| P0-U6 | Ubuntu 24.04 cloud image, base template, snapshot | Boots, snapshot restores | [ ] |
| P0-U7 | Zotero and literature matrix | 15+ entries | [ ] |
| P0-U8 | RQ v0 and gap analysis | `docs/specs/research-questions.md` | [ ] |
| P0-U9 | P1 spec | `docs/specs/P1-cluster.md` approved | [ ] |
| P0-U10 | AWS cert and CKS decision | Short ADR | [ ] |

## Unit details

Each entry records the objective, rationale, deliverables, implementation, verification and status of one unit. Fields follow the bolt template in [docs/AIDLC_Master_Plan.md](../AIDLC_Master_Plan.md). Commits are on `main` unless a branch is named.

### P0-U1: Repository skeleton

**Objective.** Establish a fixed repository structure for all project artifacts.

**Rationale.** Later phases place infrastructure code, attack scenarios, collection pipelines, models and paper sources in separate directories. A fixed layout avoids reorganisation after work has started.

**Deliverables.**
- Directories `infra/`, `k8s/`, `attacks/`, `collect/`, `ml/`, `experiments/`, `paper/`, `docs/specs/`, `docs/adr/`, `docs/reports/`. Empty directories carry a `.gitkeep` file.
- `README.md`: project summary and links to the plan, specs, decisions and assistant conventions.
- `.gitignore`: excludes kubeconfig files, packet captures (`*.pcap`), VM disk images (`*.qcow2`, `*.img`), keys and certificates, `.env` and `data/raw/`.
- `Makefile`: default target `help`, which lists documented targets.

**Verification.** The directory tree exists and `make help` runs.

**Status.** Done. Commit `9990bfb`.

### P0-U2: Assistant context file (CLAUDE.md)

**Objective.** Record project conventions in a file that is loaded at the start of every assistant session.

**Rationale.** The assistant does not retain state between sessions. A versioned context file keeps lab rules, repository layout and git workflow consistent across sessions.

**Deliverables.** `CLAUDE.md` containing:
- the working method (phases, units, bolts, ADRs, experiment log);
- lab rules: attacks only inside the isolated libvirt network, VM snapshot before each attack run and hardening change, a dedicated kubeconfig, no secrets in the repository, raw captures kept outside git;
- the division of work: core logic is written by the researcher, scripts and documentation are drafted by the assistant, and the assistant does not produce experimental results or citations;
- the repository layout and the git workflow (revised in later documentation commits).

**Verification.** The file covers isolation, kubeconfig, snapshots and the no-assistant-results rule.

**Status.** Done. Commit `9990bfb`, with later revisions to the git workflow section.

### P0-U3: Specification, ADR and experiment-log templates

**Objective.** Provide standard document formats for specifications, architecture decisions and experiments.

**Rationale.** Uniform records make decisions traceable and allow every reported result to be linked to a commit, configuration and dataset version.

**Deliverables.**
- `docs/specs/_template.md`: objective, hypothesis and metrics, scope, units, risks, gate, retrospective.
- `docs/adr/_template.md`: context, options considered, decision, consequences.
- `experiments/log.md`: table with date, git commit, configuration hash, dataset version, hypothesis, result and notes.

**Verification.** The three templates exist. Each has one example entry: ADR-001 for the ADR template and a marked dry-run row in `experiments/log.md`. The specification template is exercised by this document.

**Status.** Done. Templates in commit `9990bfb`, example entries on branch `docs/p0-updates`.

### P0-U4: KVM and libvirt installation

**Objective.** Provide hardware-accelerated virtualization and a VM and network management layer on the lab host.

**Rationale.** All cluster nodes run as KVM guests. KVM provides near-native performance, and libvirt defines and manages the guests and their virtual networks. P0-U5, P0-U6 and Phase 1 depend on this unit.

**Deliverables.**
- Host packages: `qemu-kvm`, `libvirt-daemon-system`, `libvirt-clients`, `virtinst`, `bridge-utils`, `cpu-checker`, `cloud-image-utils`.
- Membership of the operating user in the `libvirt` and `kvm` groups, so that libvirt can be managed without root.
- Evidence: [docs/reports/P0-U4-libvirt-evidence.md](../reports/P0-U4-libvirt-evidence.md).

**Implementation.** Packages installed with `apt`, the `libvirtd` service enabled, the user added to both groups, and a new login session started so that the group membership applies.

**Verification.** `virt-host-validate qemu` reports no failed checks, `kvm-ok` reports that KVM acceleration can be used, and `virsh -c qemu:///system list --all` connects. Two warnings are reported: the cgroup `devices` controller (not exposed under cgroup v2) and secure guest support (a confidential-computing feature). Neither is used by the lab.

**Reference comparison.** libvirt on one host corresponds to the control plane of a cloud provider, comparable to EC2 and VPC.

**Status.** Done. Branch `feat/p0-u4-libvirt`.

### P0-U5: Isolated libvirt network

**Objective.** Provide a virtual network for the lab guests that has no route to the home LAN or the internet.

**Rationale.** Attack scenarios run inside the lab. Isolation must hold by construction rather than depend on firewall rules. The design choice and the build-time internet policy are recorded in [ADR-001](../adr/ADR-001-lab-network-isolation.md).

**Deliverables.**
- `infra/libvirt/kg-lab-net.xml`: libvirt network `kg-lab`. Bridge `virbr-kg`, subnet `10.77.0.0/24`, gateway `10.77.0.1`, DHCP range `10.77.0.100-10.77.0.199`. The definition has no `<forward>` element, so libvirt installs no NAT and no routing for it.
- `infra/libvirt/test-isolation.sh`: acceptance script. Host-side checks cover network state, absence of `<forward>`, subnet and absence of a masquerade rule. When given two VM addresses and an SSH user, it also checks that VM A reaches VM B and cannot reach the LAN gateway or `1.1.1.1`.
- Makefile targets `net-up`, `net-down`, `net-test`.
- [ADR-001](../adr/ADR-001-lab-network-isolation.md) and evidence [docs/reports/P0-U5-network-evidence.md](../reports/P0-U5-network-evidence.md).

**Implementation.** The subnet was chosen to avoid the home LAN (`172.16.212.0/23`, `172.16.214.0/23`), Docker (`172.17.0.0/16` to `172.21.0.0/16`) and the default libvirt network (`192.168.122.0/24`). `make net-up` runs `virsh net-define`, `net-autostart` and `net-start`. `make net-test` runs the acceptance script.

**Verification.** Host-side checks pass: network active, no `<forward>`, subnet `10.77.0.0/24`, no masquerade rule. In-VM checks are pending the guests created in P0-U6.

**Reference comparison.** The network corresponds to a VPC subnet with no internet gateway, no NAT gateway and no peering, whose route table contains only the local route. The isolation script corresponds to a reachability analysis that finds no path to the LAN.

**Status.** In progress. Branch `feat/p0-u5-network`. Host-side checks verified on 2026-10-09. In-VM checks are completed in P0-U6, after which the status becomes done.

## Initial environment

- The CPU reports hardware virtualization flags (`svm`), and the `kvm` and `kvm_amd` kernel modules are loaded.
- At the start of the phase, `virt-host-validate` and `virsh` were not installed.

## Risks

- Network isolation misconfigured, so VMs reach the LAN. Test this explicitly in P0-U5.
- Literature already covers the idea. Treat as input to refine the angle.

## Gate

G0: gap is real and RQs are final. Record in `docs/adr/ADR-G0-literature-gap.md`.

## Retrospective

(Filled at phase exit.)


## Review notes

Items found in the AI-DLC review of Phase 0. Each is a work item.

1. Approval: this specification has status `draft` and has not been approved, although construction has started. Approval is required.
2. P0-U5: the build-time internet policy is documented in ADR-001. The `kg-build` network and the in-VM isolation tests are completed in P0-U6.
3. Unit details: P0-U5 and later units receive their detail entry when their acceptance check passes.
