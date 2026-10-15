# P2: Security hardening

Status: approved
Approved by / date: shaedgalib (researcher), 2026-10-15

## Objective

Harden the Phase 1 cluster measurably, one control at a time, and document each control with a test that proves it works. The hardened cluster is the target of the attacks in Phase 3, so the controls must be understood, reproducible and stable. Every control is applied through the repository (Ansible roles, manifests, Makefile targets), so that `make rebuild` produces the hardened cluster and the baseline is the same on every rebuild.

## Hypothesis and metrics

Phase 2 is an engineering phase and has no research hypothesis. It supports [research-questions.md](research-questions.md) by fixing the security baseline against which attacks (Phase 3) and detectors (Phase 4) are judged: what the hardened cluster already blocks, and what is left for detection. Measures, all taken from runs on the lab and never estimated:
- CIS benchmark and kubescape results before any change and after each group of fixes, as the tools report them (counts of passed, failed and warned checks), with the scanner versions.
- Number of controls and policies with a passing negative test (a test that shows the bad action is blocked).
- Rebuild time with the hardening included, against the 810 s measured in P1 ([docs/reports/P1-U11-U13-rebuild-evidence.md](../reports/P1-U11-U13-rebuild-evidence.md)) and the 40 minute target.
- Idle memory use added by the new components (policy engine, mTLS, scanners), against the node budget of 3 GiB (control plane) and 5 GiB (workers).

## Scope

In scope:
- Baseline scans with kube-bench (CIS Kubernetes benchmark) and kubescape, saved before any change.
- Fixes of the findings that apply to a kubeadm cluster: kubelet authentication and authorisation, anonymous access, file permissions, API server and other control plane flags.
- RBAC audit down to least privilege; Pod Security Admission at the `restricted` level for workload namespaces.
- Default-deny `CiliumNetworkPolicy` per namespace with explicit allow rules.
- etcd encryption at rest; API server audit policy with log rotation.
- Kyverno policies: no privileged pods, resource limits required, image registry allowlist.
- Service-to-service mTLS (choice recorded in an ADR).
- Image scanning with Trivy and a secrets workflow.
- A negative test for every control, runnable with `make`.
- A table mapping each control to its EKS equivalent.
- Hardening report v1 with before and after scores.

Out of scope: workloads and attacks (Phase 3), detection and runtime tools such as Falco and Tetragon (Phases 4 and 5), a highly available control plane, cloud-specific services, and any claim that the cluster is "secure" beyond what the tests show.

## Design decisions to confirm

Names follow [docs/naming.md](../naming.md). Accepted by the researcher on 2026-10-15 as the working plan for Phase 2. Any change found necessary during the build is recorded under "Amendments" below, and becomes an ADR where it is a major choice. Some choices are made later, by design: the mTLS option (H6, decided by ADR in P2-U8) and the scanner and policy engine versions (pinned when each unit starts).

| # | Decision | Proposed default | Why |
|---|---|---|---|
| H1 | Scanners | kube-bench run as Jobs on the nodes; kubescape CLI from the host with the project kubeconfig. Versions pinned in `infra/versions.env` after checking each project's release page | Two views of the same cluster; both read-only |
| H2 | Method | Scan first, then fix finding by finding, re-scan after each group. Before every change: VM snapshot and an etcd snapshot (`make vms-snapshot`, `make etcd-snapshot`) | Lab rule; a wrong API server flag can lock the control plane |
| H3 | Reproducibility | Every control lives in an Ansible role, manifest or Makefile target and is added to `make cluster`; nothing is changed by hand on a node | The gate requires a stable, rebuildable cluster |
| H4 | Pod admission | Pod Security Admission `restricted` on workload namespaces (with exemptions for `kube-system` and the Cilium namespace); Kyverno for custom rules (limits, registry allowlist, no privileged) | PSA is built in and cheap; Kyverno covers what PSA cannot. The overlap on "no privileged" is intentional and documented |
| H5 | Network policy | Default-deny per namespace, allows written by the researcher first and derived from Hubble flows. Allows kept for DNS, monitoring scrapes, Hubble and Gateway traffic | CLAUDE.md: network policies are core work for the researcher; Hubble shows what real traffic must stay |
| H6 | mTLS | Evaluate Cilium mutual authentication first; Istio ambient and Linkerd as the alternatives; decide by ADR in P2-U8 after reading the documentation for the pinned Cilium version | Cilium is already installed (no extra component or RAM); maturity of the feature must be checked, not assumed |
| H7 | Secrets workflow | SOPS with age for secrets kept in the repository (encrypted); the age private key stays outside the repository. External Secrets only if a backend is added | The isolated lab has no external secret store |
| H8 | etcd encryption | `EncryptionConfiguration` on the API server, key on the control-plane node and backed up outside the repository; existing Secrets re-encrypted; verified with `etcdctl` | A lost key makes the Secrets unreadable, so the key backup is part of the unit |
| H9 | Audit | Policy with `Metadata` level for most requests and a higher level for sensitive resources, log rotation flags set, log directory size watched | Audit logs are also an input for Phase 4; the disk budget is small |
| H10 | Gate evidence | G1 is judged on: `make rebuild` including the hardening passes, the P1 acceptance checks still pass, a re-scan reproduces the after scores, and all negative tests pass | "Stable and reproducible" must be testable |

## Units

| Unit | Description | Acceptance check | Branch | Status |
|---|---|---|---|---|
| P2-U1 | Baseline scans: kube-bench and kubescape, before any change | Scores saved under `docs/reports/` | `feat/p2-baseline-hardening` | [x] |
| P2-U2 | Fix CIS findings: kubelet auth, anonymous access, file permissions, API server flags | Re-scan shows each fix | `feat/p2-baseline-hardening` | [ ] |
| P2-U3 | RBAC audit to least privilege | Audit report, no wildcard roles outside system | `feat/p2-access-control` | [ ] |
| P2-U4 | Pod Security Admission at restricted | Privileged pod rejected | `feat/p2-access-control` | [ ] |
| P2-U5 | Default-deny CiliumNetworkPolicy per namespace plus explicit allows | Unlisted traffic dropped, listed traffic passes | `feat/p2-network-security` | [ ] |
| P2-U6 | etcd encryption at rest, API audit policy, log rotation | Secret unreadable in etcd, audit log present | `feat/p2-baseline-hardening` | [ ] |
| P2-U7 | Kyverno policies: no privileged, limits required, registry allowlist | Each policy blocks its violation | `feat/p2-access-control` | [ ] |
| P2-U8 | Service-to-service mTLS (ADR) | mTLS verified between two services | `feat/p2-network-security` | [ ] |
| P2-U9 | Trivy image scanning and secrets workflow | Vulnerable image flagged, secret decrypts only in cluster | `feat/p2-supply-chain` | [ ] |
| P2-U10 | Negative tests per control | One passing negative test per policy, runnable via make | `feat/p2-tests-report` | [ ] |
| P2-U11 | Control-to-EKS mapping table | Table covers IRSA, GuardDuty, managed control plane and others | `feat/p2-tests-report` | [ ] |
| P2-U12 | Hardening report v1 with before/after scores | Report reproducible from the repository | `feat/p2-tests-report` | [ ] |
| P2-U13 | Phase 3 spec | `docs/specs/P3-data.md` approved | `docs/p2-p3-spec` | [ ] |

## Branches

The 13 units do not need 13 branches; they are grouped by what they change. Each branch follows the flow in CLAUDE.md. The names were approved with the spec.

| Branch | Units | Acceptance for the branch |
|---|---|---|
| `feat/p2-baseline-hardening` | P2-U1, U2, U6 | Baseline saved, CIS fixes re-scanned, Secret encrypted in etcd, audit log present |
| `feat/p2-access-control` | P2-U3, U4, U7 | No wildcard roles, privileged pod rejected by PSA, each Kyverno policy blocks its violation |
| `feat/p2-network-security` | P2-U5, U8 | Default-deny proven, mTLS verified, P1 checks still pass |
| `feat/p2-supply-chain` | P2-U9 | Vulnerable image flagged, secret decrypts only in the cluster |
| `feat/p2-tests-report` | P2-U10, U11, U12 | All negative tests pass with make, mapping table and report written |
| `docs/p2-p3-spec` | P2-U13 | Phase 3 spec approved |

Order of work: U1 first (nothing is changed before the baseline exists), then U2 and U6 on the control plane, then U3, U4 and U7, then U5 and U8 (these can break the monitoring and the sample app, so they come after the access controls), then U9, then U10 to U12, then U13. After every branch: run the P1 acceptance checks (`net-test-u6`, `net-test-u7`, `net-test-u8`) so a control that breaks the cluster is found at once.

## Unit plan

| Unit | Depends on | Produces | Researcher decides or writes first | Assistant helps with |
|---|---|---|---|---|
| P2-U1 | P1 done, H1 | Scanner install targets, `docs/reports/P2-U1-baseline.md` | Which scan profiles to run | Targets, Job manifests, saving the raw output |
| P2-U2 | U1 | Ansible role `hardening` (kubelet, API server, file modes), re-scan report | Which findings to fix and which to accept with a reason | Role tasks, idempotence test, report |
| P2-U3 | U1 | RBAC audit report, trimmed roles | Which access is really needed | Audit script, report |
| P2-U4 | U3 | Namespace labels, manifests | Exemptions | Test pods, `make` target |
| P2-U5 | U4 | `k8s/policies/` CiliumNetworkPolicies per namespace | The policies themselves (core work) | Hubble-based review, tests that show dropped and passed traffic |
| P2-U6 | U2 | EncryptionConfiguration, audit policy, role changes | Audit levels, key handling | Role tasks, verification with `etcdctl` |
| P2-U7 | U4 | Kyverno install and policies | Which rules and which exceptions | Install target, policy drafts, tests |
| P2-U8 | U5, H6 | ADR and mTLS manifests | The mTLS option | Verification test |
| P2-U9 | U7 | Trivy target, SOPS workflow | The secrets flow | Targets, test with a known vulnerable image |
| P2-U10 | U2 to U9 | `make test-hardening` and one negative test per control | What counts as "blocked" | Test scripts |
| P2-U11 | U2 to U9 | `docs/hardening/eks-mapping.md` | The EKS side (the researcher's AWS knowledge) | Table layout, checking claims against documentation |
| P2-U12 | U10 | `docs/reports/P2-hardening-report-v1.md` | Interpretation of the scores | Layout, tables from the saved outputs |
| P2-U13 | G1 | `docs/specs/P3-data.md` | Scope of the dataset and attacks | Draft from the research plan |

The assistant never produces the benchmark numbers: they come from the scanners, run by the researcher, and are copied unchanged into the reports.

## In AWS terms

| In this lab | On EKS |
|---|---|
| Hardening the API server, kubelet and etcd by hand (CIS, kube-bench) | The managed control plane: AWS operates it; nodes are still your side of the shared responsibility |
| Pod Security Admission, Kyverno | The same Kubernetes admission controls; Kyverno or Gatekeeper are also used on EKS |
| CiliumNetworkPolicy default-deny | NetworkPolicy via the VPC CNI or Cilium, plus security groups for pods |
| Audit policy and log rotation | Control plane logging to CloudWatch |
| etcd encryption at rest | Envelope encryption of Secrets with a KMS key |
| Service-to-service mTLS | A service mesh or Cilium; no managed default |
| SOPS or External Secrets | AWS Secrets Manager with External Secrets |
| Trivy | ECR image scanning and Inspector |

The full table, with the controls actually built, is the deliverable of P2-U11.

## Risks

- **A control breaks the cluster.** A wrong API server flag can stop the control plane; default-deny can cut DNS, monitoring or the Gateway. Mitigation: VM and etcd snapshots before each change (H2), small steps, the P1 acceptance checks after each branch, changes through Ansible so they can be reverted and rebuilt.
- **Locking myself out.** Mitigation: keep a copy of the static pod manifests before editing; the etcd restore runbook and `make vms-restore`.
- **Pod Security `restricted` and system components.** Cilium, node-exporter and parts of the monitoring stack need privileges. Mitigation: namespace exemptions that are explicit and documented, not a weaker level everywhere.
- **Kyverno can block the cluster itself.** A failing admission webhook can stop pod creation. Mitigation: exclude system namespaces and set a safe failure policy; test in a non-system namespace first.
- **RAM.** Kyverno, an mTLS option and scanners add pods. Mitigation: measure idle use after each addition; the nodes can be resized with `make vms-resize`.
- **Lost encryption key.** Secrets would be unreadable. Mitigation: H8, key backup outside the repository, restore tested.
- **Audit log growth.** Mitigation: rotation flags, a size check, a policy that logs most requests at `Metadata` level only.
- **Misreading scores.** Some CIS checks do not apply to kubeadm or to this lab, and a better score is not proof of security. Mitigation: each unchanged finding gets a recorded reason; the negative tests, not the score alone, are the evidence.
- **Secrets in the repository.** Mitigation: SOPS with the key outside the repository (H7); no plain secrets are committed.

## Gate

G1, at the end of Phase 2: the cluster is stable and reproducible after hardening. Pass condition (H10): `make rebuild` with the hardening included completes and the P1 acceptance checks pass; a re-scan reproduces the after scores; every control has a passing negative test. If it fails, fix before generating any data in Phase 3. The result is recorded in `docs/adr/ADR-G1-*.md`.

## Amendments

Changes to the approved plan during Phase 2. One line each: date, decision number, change, reason.

(None yet.)

## Retrospective (filled at phase exit)

(Filled at phase exit.)
