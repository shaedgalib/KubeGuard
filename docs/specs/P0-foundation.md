# P0: Foundation (lab, repo, literature)

Status: approved
Approved by / date: shaedgalib (researcher), 2026-10-09

## Objective

Prepare the repo and the isolated lab, and check that the research gap is real before building the cluster.

## Hypothesis and metrics

Hypothesis: there is room for a Kubernetes security dataset and benchmark that combines flow, runtime and audit signals, with benign changes (rollouts, autoscaling) included.
Metrics: 15+ papers in the literature matrix, and a written G0 decision.

## Scope

In scope: repo skeleton, assistant context files, templates, KVM/libvirt, isolated network, base VM image, literature matrix, RQ v0, P1 spec.
Out of scope: Kubernetes install (P1), any attack work.

## Units

| Unit | Description | Acceptance check | Status |
|---|---|---|---|
| P0-U1 | Repo skeleton, README, Makefile | Tree exists, `make help` runs | [x] |
| P0-U2 | CLAUDE.md | Covers isolation, kubeconfig, snapshots, no-AI-numbers | [x] |
| P0-U3 | Spec, ADR, experiment-log templates | Templates present | [x] |
| P0-U4 | KVM/libvirt installed | `virt-host-validate` passes | [x] |
| P0-U5 | Isolated libvirt network | VMs reach each other, cannot reach home LAN (tested) | [x] |
| P0-U6 | Ubuntu 24.04 cloud image, base template, snapshot | Boots, snapshot restores | [x] |
| P0-U7 | Literature matrix | 15+ entries | [x] |
| P0-U8 | RQ v0 and gap analysis | `docs/specs/research-questions.md` | [x] |
| P0-U9 | P1 spec | `docs/specs/P1-cluster.md` approved | [x] |

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
- `infra/libvirt/clone-test-vms.sh` and `infra/cloud-init/clone-user-data.tpl`: clone `kg-base` into two test VMs on `kg-lab` only, and run the in-VM checks.
- [ADR-001](../adr/ADR-001-lab-network-isolation.md) and evidence [docs/reports/P0-U5-network-evidence.md](../reports/P0-U5-network-evidence.md).

**Implementation.** The subnet was chosen to avoid the home LAN (`172.16.212.0/23`, `172.16.214.0/23`), Docker (`172.17.0.0/16` to `172.21.0.0/16`) and the default libvirt network (`192.168.122.0/24`). `make net-up` runs `virsh net-define`, `net-autostart` and `net-start`. `make net-test` runs the acceptance script.

**Verification.** All checks pass. Host side: network active, no `<forward>`, subnet `10.77.0.0/24`, no masquerade rule. In two clones of the P0-U6 base VM: VM A reaches VM B, VM A cannot reach the LAN gateway `172.16.212.1` and cannot reach the internet. The default-route gateway is the one tested; the second host LAN route (`172.16.214.1`) is not covered by the script.

**Reference comparison.** The network corresponds to a VPC subnet with no internet gateway, no NAT gateway and no peering, whose route table contains only the local route. The isolation script corresponds to a reachability analysis that finds no path to the LAN.

**Status.** Done. Network and host-side checks on branch `feat/p0-u5-network`; in-VM checks completed on 2026-10-09 on branch `feat/p0-u6`.

### P0-U6: Base VM image and snapshot

**Objective.** Provide a verified Ubuntu 24.04 base VM with a restorable snapshot, from which lab nodes are cloned.

**Rationale.** Every lab node starts from the same known state. A snapshot allows a return to that state before each attack run and hardening change, as required by the lab rules. Resource use is kept minimal (1 vCPU, 1 GiB RAM, 10 GiB thin disk) and is increased only when a later phase requires it.

**Deliverables.**
- Storage pool `kg-images` at `/var/lib/libvirt/images/kubeguard` (host, not in git) holding `noble-base.img`, the checksum-verified Ubuntu 24.04 cloud image.
- `infra/libvirt/kg-build-net.xml`: temporary NAT network `kg-build` (`10.78.0.0/24`) for builds, as defined in [ADR-001](../adr/ADR-001-lab-network-isolation.md).
- `infra/cloud-init/user-data.tpl` and `meta-data`: user `ubuntu` with key-only login and passwordless sudo, packages `qemu-guest-agent`, `curl`, `jq`, system upgrade, power-off on completion. The SSH public key is injected at build time and is not stored in git.
- `infra/libvirt/build-base-vm.sh`: `create`, `snapshot`, `restore-test`, `destroy`. Makefile targets `build-net-up`, `build-net-down`, `base-vm`, `base-snapshot`, `base-restore-test`, `base-destroy`.
- Snapshot `base-clean` of VM `kg-base`.
- Evidence: [docs/reports/P0-U6-base-image-evidence.md](../reports/P0-U6-base-image-evidence.md).

**Implementation.** The image was downloaded from `cloud-images.ubuntu.com` and verified with `sha256sum -c`. A dedicated lab key pair (`~/.ssh/kubeguard-lab`) was generated, separate from any GitHub or work key. `make build-net-up` and `make base-vm` created the network and the VM, which provisioned itself through cloud-init and powered off. `make base-snapshot` created `base-clean`.

**Verification.** `make base-restore-test` boots the VM, writes a marker file, reverts to `base-clean`, boots again and confirms that the marker is gone. The test passed. It also confirms SSH access with the lab key.

**Reference comparison.** The base image corresponds to an AMI, the cloud-init file to EC2 user data, and the snapshot to an EBS snapshot used to restore a known state.

**Status.** Done. Branch `feat/p0-u6`. Interface of `kg-base` is on `kg-build`; lab clones use `kg-lab` only.

### P0-U7: Literature matrix

**Objective.** Establish what prior work exists for the three research questions, as input to the research-gap decision at G0.

**Rationale.** The project claims room for a Kubernetes security dataset that combines flow, runtime and audit signals, with benign operational changes included. This claim is checked against the literature before the cluster is built.

**Deliverables.**
- [docs/literature/README.md](../literature/README.md): scope (three areas, five or more papers each), verification rules and search keywords.
- [docs/literature/matrix.md](../literature/matrix.md): matrix with 36 entries. 27 are verified at metadata level against Crossref, DataCite, arXiv or the primary document; 5 were checked against a host page only; 4 were not checked.
- [docs/literature/gap-checklist.md](../literature/gap-checklist.md): eight questions answered during reading, feeding P0-U8 and G0.

**Implementation.** Leads were collected by web search. The source pages were then read and the matrix records authors, venue, year, DOI and what the page states about data, method, attack coverage, baselines and limitations. Entries were then compared with Crossref, DataCite, the arXiv API or the primary document. No reference manager is used; references enter `paper/refs.bib` when a paper is cited.

**Verification.** At least 15 entries with `Verified = yes`. Result: 27 of 36, verified by the assistant on the researcher's instruction. Evidence: [docs/reports/P0-U7-verification.md](../reports/P0-U7-verification.md). The check covers existence and metadata, not quality; papers are read before they are cited.

**Status.** Done. Branch `docs/p0-updates`. Open items for later phases: answers in the gap checklist are provisional and feed P0-U8 and G0.

### P0-U8: Research questions v0 and gap analysis

**Objective.** State the research questions in testable form and the gap that justifies them, with the evidence from the literature.

**Rationale.** Gate G0 requires a written decision on whether the gap is real before the cluster is built. The questions also fix what the later phases must measure.

**Deliverables.**
- [docs/specs/research-questions.md](research-questions.md): problem statement, RQ1 to RQ3 with outcome measures and sub-questions, gap analysis G1 to G6 with matrix IDs and strength ratings, threats to the analysis, scope and non-goals, G0 proposal.
- [ADR-G0](../adr/ADR-G0-literature-gap.md): the gate decision.

**Implementation.** The questions come from the programme plan and were sharpened with the literature results. The closest sources (L01, L03, L24, L30, L32) were read in full, and every gap statement cites matrix entries.

**Verification.** The file exists and was approved by the researcher on 2026-10-09. The gate pass rule is met: G1 and G4 hold.

**Status.** Done. Branch `docs/p0-updates`. G0 passed on 2026-10-09; G1 is to be re-checked when the L01 data files are available.

### P0-U9: Phase 1 specification

**Objective.** Specify Phase 1 (the cluster) before any build work starts, so that its scope, units, decisions and risks are approved in advance.

**Rationale.** AI-DLC requires an approved specification before construction. Phase 1 depends on the P0 lab (isolated network, base image) and on the P0-U8 decisions, so the specification is written once those exist.

**Deliverables.**
- [docs/specs/P1-cluster.md](P1-cluster.md): objective, scope, nine design decisions (D1 to D9), the 14 units with acceptance checks, a unit plan with dependencies and division of work, risks, the gate statement, and an amendments log.

**Implementation.** The units and acceptance checks come from the master plan. The design decisions were added to fix choices that affect several units: node sizing (started small), node addresses, cluster CIDRs outside the lab and host ranges, the MetalLB pool, build-time internet through `kg-build` (ADR-001), image supply, ingress, version pinning and the Ansible inventory.

**Verification.** The specification was approved on 2026-10-09, with D1 to D9 accepted as the working plan for Phase 1. Changes found necessary during the build are recorded in its Amendments section.

**Status.** Done. Branch `feat/p0-u9-p1-spec`.

## Initial environment

- The CPU reports hardware virtualization flags (`svm`), and the `kvm` and `kvm_amd` kernel modules are loaded.
- At the start of the phase, `virt-host-validate` and `virsh` were not installed.

## Risks

- Network isolation misconfigured, so VMs reach the LAN. Test this explicitly in P0-U5.
- Literature already covers the idea. Treat as input to refine the angle.

## Gate

G0: gap is real and RQs are final. Record in `docs/adr/ADR-G0-literature-gap.md`.

## Retrospective

Phase result: Phase 0 is complete. Units U1 to U9 are done and gate G0 passed on 2026-10-09 ([ADR-G0](../adr/ADR-G0-literature-gap.md), accepted). Tag `p0-done`.

**What worked**
- The base image and its snapshot: the restore test and the isolation checks on two clones both passed, with evidence saved under `docs/reports/`.
- One feature branch per unit with `--no-ff` merges kept the history readable and each unit revertable.
- Checking literature entries against Crossref, DataCite and the arXiv API, and reading the closest sources in full, caught real errors (wrong author order for L32, a wrong year for L28, and a search result tied to the wrong paper for L25) and sharpened the gap analysis.
- Recording decisions as ADRs (network isolation, the G0 gate) made later units simpler to specify.

**What slipped or went wrong**
- Construction started before the specification was approved. The gap was found in review and closed on 2026-10-09.
- Early in the work the assistant pushed, merged and deleted branches without asking, and once merged `dev` into a feature branch. These were corrected, and the rules are now in CLAUDE.md.
- The first cloned test VM got no network address, because its generated network configuration matched the base image's MAC address. Per-clone cloud-init seeds fixed it. A `pipefail` bug in the build script reported a healthy network as inactive; it was fixed the same day.
- The first literature pass was abstract level and produced a wrong paper mapping. The gap analysis changed after full texts were read.

**Scope changes**
- The AWS certification and CKS decision unit (U10) was removed as out of project scope.
- Zotero was not used. The matrix is kept in the repository and verified against official records.
- The "bare-metal" claim was dropped because the lab runs in KVM virtual machines.
- Node and VM sizes start minimal and grow only when a unit needs it.
- The assistant may propose reference leads from web search, marked unverified, and check their metadata. This was added to CLAUDE.md.

**Carried into Phase 1**
- `kg-base` still has its interface on `kg-build`. Lab nodes must use `kg-lab` only, and `kg-build` is attached only during builds (ADR-001).
- The test VMs `kg-t1` and `kg-t2` and the `kg-build` network still exist. Remove the VMs when no longer needed with `infra/libvirt/clone-test-vms.sh destroy`.
- Re-check gap G1 when the L01 dataset files are available (expected after about 11 October 2026), and before any paper submission.
- Pin component versions in P1-U2, and record node sizing in an ADR.
- Zotero is installed under `~/opt/zotero-install` and is not used by the project.


## Review notes

Items found in the AI-DLC review of Phase 0. Each is a work item.

1. Approval: the specification was approved on 2026-10-09, after construction of U1 to U8 had started. The units added since then (U9) follow the approved scope.
2. P0-U5 and P0-U6 are done. Remaining for ADR-001: the build-time policy (`kg-build` detached before attack work) is documented, and `kg-base` still has its interface on `kg-build`.
3. Unit details: later units receive their detail entry when their acceptance check passes.
