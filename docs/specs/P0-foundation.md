# P0: Foundation (lab, repo, literature)

Status: draft (awaiting your approval)
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
| P0-U4 | KVM/libvirt installed | `virt-host-validate` passes | [ ] |
| P0-U5 | Isolated libvirt network | VMs reach each other, cannot reach home LAN (tested) | [ ] |
| P0-U6 | Ubuntu 24.04 cloud image, base template, snapshot | Boots, snapshot restores | [ ] |
| P0-U7 | Zotero and literature matrix | 15+ entries | [ ] |
| P0-U8 | RQ v0 and gap analysis | `docs/specs/research-questions.md` | [ ] |
| P0-U9 | P1 spec | `docs/specs/P1-cluster.md` approved | [ ] |
| P0-U10 | AWS cert and CKS decision | Short ADR | [ ] |

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
