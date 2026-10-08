# P0: Foundation (lab, repo, literature)

Status: draft (awaiting your approval; construction already started, see Open process items)
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
| P0-U5 | Isolated libvirt network | VMs reach each other, cannot reach home LAN (tested) | [ ] |
| P0-U6 | Ubuntu 24.04 cloud image, base template, snapshot | Boots, snapshot restores | [ ] |
| P0-U7 | Zotero and literature matrix | 15+ entries | [ ] |
| P0-U8 | RQ v0 and gap analysis | `docs/specs/research-questions.md` | [ ] |
| P0-U9 | P1 spec | `docs/specs/P1-cluster.md` approved | [ ] |
| P0-U10 | AWS cert and CKS decision | Short ADR | [ ] |

## Unit details

Each unit below explains what it is for, what was actually created, and how to check it. Written for someone new to the project. Template: the bolt template in [docs/AIDLC_Master_Plan.md](../AIDLC_Master_Plan.md). Commit hashes are on `main`.

### P0-U1: Repo skeleton

- **Use case:** one predictable place for every kind of artifact (infra, attacks, data collection, ML, paper), so later phases never need to reorganise the repo.
- **Created:** top-level folders `infra/`, `k8s/`, `attacks/`, `collect/`, `ml/`, `experiments/`, `paper/`, `docs/{specs,adr,reports}/`; `README.md`; `.gitignore` (blocks kubeconfigs, pcaps, VM images, keys, `.env`, raw data); `Makefile` with a `help` target. Empty folders hold a `.gitkeep`.
- **Verify:** `ls` shows the tree, `make help` runs.
- **Bolt notes:** commit `9990bfb`. Status: done.

### P0-U2: CLAUDE.md

- **Use case:** the AI assistant forgets everything between sessions. This file carries the rules, so the same lab and git conventions apply every time.
- **Created:** `CLAUDE.md` with the method (phases, units, bolts), the non-negotiable lab rules (isolated network only, snapshot before attacks and hardening, project-only kubeconfig, no secrets, no raw pcaps in git), the division of work (you write core logic, the assistant writes scripts and docs, no AI-made numbers or citations), the repo layout, and the git workflow. The git workflow and the no-attribution rule were revised later on feature branches.
- **Verify:** it covers isolation, kubeconfig, snapshots and no-AI-numbers.
- **Bolt notes:** commit `9990bfb`, updated in later docs commits. Status: done.

### P0-U3: Templates

- **Use case:** every spec, decision and experiment has the same shape, so results can be traced and compared later.
- **Created:** `docs/specs/_template.md` (objective, hypothesis, scope, units, risks, gate, retrospective), `docs/adr/_template.md` (context, options, decision, consequences), `experiments/log.md` (table: date, commit, config hash, dataset version, hypothesis, result).
- **Verify:** templates present. The master plan also asks for one dry-run entry in each; see "Open process items" below.
- **Bolt notes:** commit `9990bfb`. Status: done, dry-run entries pending.

### P0-U4: KVM/libvirt installed

- **Use case:** the lab runs as three virtual machines on this laptop. KVM gives near-native VM speed, and libvirt is the tool that creates and manages VMs and their networks. Think of it as a small private cloud provider (like EC2 plus VPC) on your own machine.
- **Created:** nothing in the repo except evidence. On the host: packages `qemu-kvm`, `libvirt-daemon-system`, `libvirt-clients`, `virtinst`, `bridge-utils`, `cpu-checker`, `cloud-image-utils`; your user added to the `libvirt` and `kvm` groups.
- **Verify:** `virt-host-validate qemu` shows no FAIL. Evidence: [docs/reports/P0-U4-libvirt-evidence.md](../reports/P0-U4-libvirt-evidence.md).
- **Bolt notes:** branch `feat/p0-u4-libvirt`. Two WARNs (cgroup `devices`, secure guest) are harmless. Status: done.

## Environment findings (from first check)

- CPU exposes virtualization flags (16 hardware threads report vmx/svm), so KVM should work.
- `virt-host-validate` and `virsh` are not installed. P0-U4 starts from zero.

## Risks

- Network isolation misconfigured, so VMs reach the LAN. Test this explicitly in P0-U5.
- Literature already covers the idea. Treat as input to refine the angle.

## Gate

G0: gap is real and RQs are final. Record in `docs/adr/ADR-G0-literature-gap.md`.

## Retrospective

(Filled at phase exit.)

## Open process items

Found during an AI-DLC review of the work so far.

- This spec is still `draft` and unapproved, yet construction started. The human approval step was skipped. Approve it (or amend it) to close this.
- P0-U3 asks for one dry-run entry each in `experiments/log.md` and `docs/adr/`. Not done yet.
- P0-U5 needs the "internet-only-as-needed" policy written and tested. This needs an ADR (isolation design and build-time internet).
- Each unit gets its unit-details entry before it is ticked done. Done for U1 to U4; U5 follows once its test passes.
