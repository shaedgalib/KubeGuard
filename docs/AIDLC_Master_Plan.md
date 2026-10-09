# KubeGuard: AI-DLC Master Plan

Source: [KubeGuard_Research_Plan.md](../KubeGuard_Research_Plan.md) v1.0. This document restructures that plan under the AI-Driven Development Lifecycle (AI-DLC). It has no calendar. Progress is driven by **bolts** (short work cycles) and **gates** (go/no-go decisions), not by weeks.

Status legend: `[ ]` not started, `[~]` in progress, `[x]` done.
Unit status is kept in sync with the phase spec in `docs/specs/`. The spec also holds the per-unit details (what was created, how to verify, bolt notes).


## 1. How AI-DLC is applied here

AI-DLC has three stages: **Inception**, **Construction**, **Operations**. The AI proposes plans and drafts. The human validates and decides. Work is split into small **units**, and each unit is finished in one or more **bolts**.

| AI-DLC term | Meaning in this project |
|---|---|
| Intent | A high-level goal. Here: one per phase (P0 to P6). |
| Unit | A cohesive, independently verifiable piece of an intent (e.g. "Ansible containerd role"). |
| Bolt | One focused work cycle on a unit, hours to a few days. Ends with a passing acceptance check. |
| Mob Elaboration | Human and Claude jointly turn an intent into units, acceptance criteria and risks. Human approves. |
| Mob Construction | Human and Claude build the unit. Human writes core logic, Claude drafts the rest. |
| Context (steering) files | `CLAUDE.md`, `docs/specs/`, `docs/adr/`. They carry state between sessions. |
| Gate | Decision point between phases (G0 to G3). Outcome recorded as an ADR. |

### The loop for every phase

1. **Inception** (Mob Elaboration)
   - Write `docs/specs/PX-<name>.md`: objective, hypothesis, metrics, scope, out-of-scope, risks.
   - Break it into units. Each unit has an acceptance check written before work starts.
   - Human approves the spec. Only then does Construction begin.
2. **Construction** (Mob Construction)
   - Run bolts per unit: design (domain, then logical), implement, test, review.
   - Commit per bolt. Tag each experiment `exp/<phase>-<id>`. Log it in `experiments/log.md`.
3. **Operations**
   - Reproducibility check: lab rebuilds from the repo, results regenerate from tagged commits.
   - Update `CLAUDE.md`, ADRs and the dataset card. Retrospective note in the spec.
   - Gate decision, then the next phase starts.

### Human and AI responsibilities

| Human owns | Claude assists with |
|---|---|
| Core logic: cluster setup, network policies, detection logic | Ansible, scripts, tests, pipeline code |
| Running every experiment, all numbers and conclusions | Drafting docs, specs, ADR skeletons, LaTeX scaffolding |
| Verifying every citation | Summarising papers you supply (never inventing references) |
| Gate decisions | Reviewing diffs, finding gaps in acceptance checks |

### Bolt template

Copy into the phase spec for each unit.

```
Unit:        <id and name>
Intent:      <phase>
Depends on:  <unit ids>
Acceptance:  <observable check, command or output>
Artifacts:   <files, ADR, log entry>
Bolt notes:  <what was done, commit hash, result>
Status:      [ ]
```

### Definition of done for any unit

- Acceptance check passes and the evidence is saved or linked.
- Committed, with an ADR if a major choice was made.
- No secrets or work credentials in the repo.
- `CLAUDE.md` updated if commands or layout changed.


## 2. Inception for the whole programme

### Programme intent

Build a reproducible bare-metal Kubernetes security lab, a public labeled dataset, and detection work (flow, runtime, audit, eBPF, LLM), producing up to three papers and a portfolio for MS/PhD applications.

### Research questions (v0, refined at G0)

- RQ1: How well do flow-, runtime- and audit-level signals detect attacks in bare-metal Kubernetes versus rule baselines (Falco, Cilium verdicts)?
- RQ2: What do eBPF-derived features add, and at what CPU, memory and latency overhead versus packet capture or sidecars?
- RQ3: Can LLMs triage alerts and synthesise network policies accurately and safely, given that logs are attacker-controlled?

### Constraints

- Part-time effort next to a full-time job. Plans must survive pauses, so every unit leaves the repo in a clean, committed state.
- Hardware: Ryzen 7 8840HS, 32 GB RAM, 512 GB disk, Ubuntu 24.04, three KVM VMs (control plane 4 GB, workers 8 GB each).
- Isolated lab network only. No work or client credentials. Separate kubeconfig.

### Phase dependency graph

```
P0 Foundation ──G0──> P1 Cluster ──> P2 Hardening ──G1──> P3 Workload/Attacks/Data ──G2──> P4 Detection ──G3──> P5 eBPF ──> P6 LLM
                                                                                              (Paper 1)        (Paper 2)   (Paper 3)
```

Rule: P5 does not start until P4 evaluation is stable. If effort runs short, cut P6 first, then P5. Keep P0 to P4.

### Programme-level gates

| Gate | After | Pass condition | If it fails |
|---|---|---|---|
| G0 | P0 | Literature scan shows a genuine gap | Refine RQs before building |
| G1 | P2 | Cluster stable and reproducible after hardening | Fix before generating any data |
| G2 | P3 | Dataset has enough normal and attack coverage, and baselines do not already solve it | Shift angle to unknown attacks or false positives under benign changes |
| G3 | P4 | Paper 1 has a defensible contribution | Cut P6, possibly P5 |

Each gate result goes in `docs/adr/` as `ADR-GX-<decision>.md`.


## 3. Phase plans (Intent, Units, Acceptance)

Each phase lists its units in dependency order. Unit IDs are stable references for specs, commits and logs.

### P0: Foundation (lab, repo, literature)

**Intent:** Prepare the lab and repo, and confirm the research gap before building.
**Spec:** `docs/specs/P0-foundation.md`

| Unit | Description | Acceptance check | Status |
|---|---|---|---|
| P0-U1 | Repo skeleton per research plan section 3, README, Makefile skeleton | Directory tree exists, `make help` runs | [x] |
| P0-U2 | `CLAUDE.md` with lab rules, layout, commands | Covers isolation, kubeconfig, snapshot, no-AI-numbers rules | [x] |
| P0-U3 | Spec, ADR and experiment-log templates | Templates in `docs/`, one dry-run entry each | [x] |
| P0-U4 | KVM/libvirt installed, virtualization verified | `virt-host-validate` passes | [x] |
| P0-U5 | Isolated libvirt network, no route to home or office LAN | VMs reach each other, `ping` to LAN gateway and internet-only-as-needed policy documented and tested | [x] |
| P0-U6 | Ubuntu 24.04 cloud image, base VM template, snapshot | Base image boots and snapshot restores | [x] |
| P0-U7 | Literature matrix (paper, data, method, attack coverage, limitations) | 15+ entries across K8s anomaly detection, eBPF observability, LLMs for SecOps | [x] |
| P0-U8 | Research questions v0 and gap analysis | `docs/specs/research-questions.md` written | [ ] |
| P0-U9 | Phase 1 spec | `docs/specs/P1-cluster.md` approved | [ ] |
| P0-U10 | Decision on AWS cert renewals and CKS side track | One-paragraph ADR | [ ] |

**Gate G0:** `ADR-G0` records whether the gap is real and the final RQs.

### P1: Bare-metal Kubernetes cluster and networking

**Intent:** Reproducible kubeadm cluster with Cilium and Hubble, understood layer by layer.
**Spec:** `docs/specs/P1-cluster.md`

| Unit | Description | Acceptance check | Status |
|---|---|---|---|
| P1-U1 | Three VMs from cloud-init (infra definitions) | `make vms` creates 3 reachable VMs | [ ] |
| P1-U2 | Ansible role `common` (swap off, kernel modules, sysctl) | Idempotent re-run reports no changes | [ ] |
| P1-U3 | Ansible role `containerd` | `crictl info` OK on all nodes | [ ] |
| P1-U4 | Ansible roles kubeadm init and join | 3 nodes join, API reachable | [ ] |
| P1-U5 | Cilium with kube-proxy replacement, Hubble relay and UI | `cilium status` healthy, flows visible | [ ] |
| P1-U6 | MetalLB (L2 pool), ingress or Gateway API, local-path storage | LoadBalancer IP assigned, PVC binds | [ ] |
| P1-U7 | kube-prometheus-stack with short retention | Grafana dashboards load, RAM within budget | [ ] |
| P1-U8 | Sample app via MetalLB and ingress, flows seen in Hubble | Request from host succeeds, flow appears | [ ] |
| P1-U9 | etcd snapshot and restore drill | Restore tested, steps in runbook | [ ] |
| P1-U10 | Node drain, node failure and rejoin drills | Cluster recovers, steps in runbook | [ ] |
| P1-U11 | `make up`, `make down`, `make reset`, `make cluster` | Clean VMs to Ready cluster with one command | [ ] |
| P1-U12 | ADRs: CNI, load balancer, ingress, storage | 4 ADRs committed | [ ] |
| P1-U13 | Rebuild time measured | Documented, target under 40 minutes | [ ] |
| P1-U14 | Phase 2 spec | `docs/specs/P2-hardening.md` approved | [ ] |

Notes: confirm guest kernel has BTF (needed in P5). Study alongside: Kubernetes The Hard Way, CKA curriculum, Cilium labs.

### P2: Security hardening

**Intent:** Harden measurably, document each control, and create the baseline for attacks.
**Spec:** `docs/specs/P2-hardening.md`

| Unit | Description | Acceptance check | Status |
|---|---|---|---|
| P2-U1 | Baseline scans: kube-bench and kubescape, before any change | Scores saved under `docs/reports/` | [ ] |
| P2-U2 | Fix CIS findings: kubelet auth, anonymous access, file perms, API server flags | Re-scan shows each fix | [ ] |
| P2-U3 | RBAC audit to least privilege | Audit report, no wildcard roles outside system | [ ] |
| P2-U4 | Pod Security Admission at restricted | Privileged pod rejected | [ ] |
| P2-U5 | Default-deny CiliumNetworkPolicy per namespace plus explicit allows | Unlisted traffic dropped, listed traffic passes | [ ] |
| P2-U6 | etcd encryption at rest, API audit policy, log rotation | Secret unreadable in etcd, audit log present | [ ] |
| P2-U7 | Kyverno policies: no privileged, limits required, registry allowlist | Each policy blocks its violation | [ ] |
| P2-U8 | Service-to-service mTLS (Cilium mutual auth, Istio ambient or Linkerd; ADR) | mTLS verified between two services | [ ] |
| P2-U9 | Trivy image scanning and secrets workflow (SOPS or External Secrets) | Vulnerable image flagged, secret decrypts only in cluster | [ ] |
| P2-U10 | Negative tests per control | One passing negative test per policy, runnable via make | [ ] |
| P2-U11 | Control-to-EKS mapping table | Table covers IRSA, GuardDuty, managed control plane and others | [ ] |
| P2-U12 | Hardening report v1 with before/after scores | Report reproducible from repo | [ ] |
| P2-U13 | Phase 3 spec | `docs/specs/P3-data.md` approved | [ ] |

Rules: apply controls one at a time, snapshot before each, keep the cluster working after every unit.
**Gate G1:** cluster stable and rebuildable after hardening, recorded in `ADR-G1`.

### P3: Workload, attacks and data pipeline

**Intent:** Realistic normal traffic, scripted labeled attacks, repeatable collection.
**Spec:** `docs/specs/P3-data.md`

| Unit | Description | Acceptance check | Status |
|---|---|---|---|
| P3-U1 | Deploy Online Boutique (Train Ticket later if RAM allows) | All pods Ready, UI reachable | [ ] |
| P3-U2 | Traffic profiles with k6 or Locust: idle, steady, burst, rolling update, autoscaling | Each profile runs from a script | [ ] |
| P3-U3 | Collectors: Hubble flows, Falco events, API audit logs, Prometheus metrics (optional Zeek or Suricata) | All sources produce data with synced timestamps | [ ] |
| P3-U4 | Attack runner and attack manifest (id, type, start, end, source, target) | Manifest written for every run | [ ] |
| P3-U5 | Attack scripts, one per class: port scan, lateral movement, DoS, crypto-miner, DNS tunneling, data exfiltration, API server abuse, Kubernetes Goat scenarios | Each class runs and shows up in at least one source | [ ] |
| P3-U6 | MITRE ATT&CK for Containers mapping | Attack catalogue complete | [ ] |
| P3-U7 | Schema, Parquet export, checksums | Export validates against schema | [ ] |
| P3-U8 | Snapshot before attack session, reset after | Scripted and tested | [ ] |
| P3-U9 | Normal data collection | 72+ hours aggregated normal traffic | [ ] |
| P3-U10 | Attack campaigns | 6+ classes, 10+ runs each with varied parameters | [ ] |
| P3-U11 | Dataset card and ethics note | `docs/dataset-card.md` complete | [ ] |
| P3-U12 | Pipeline replay from repo | Fresh checkout regenerates a dataset slice | [ ] |
| P3-U13 | Dataset v0.1 published, Phase 4 spec | Public repo, `docs/specs/P4-detection.md` approved | [ ] |

Disk rule: raw pcaps go to an external drive; the repo keeps features only.
**Gate G2:** coverage adequate and baselines do not already solve it, recorded in `ADR-G2`.

### P4: Intrusion detection (Paper 1)

**Intent:** Detect the P3 attacks and benchmark against realistic baselines.
**Spec:** `docs/specs/P4-detection.md`

| Unit | Description | Acceptance check | Status |
|---|---|---|---|
| P4-U1 | Baselines: Falco default rules, Suricata (if used), Cilium policy verdicts | Baseline metrics on the dataset | [ ] |
| P4-U2 | Feature engineering per source and windowing | Feature tables versioned | [ ] |
| P4-U3 | Splits: time-based and leave-one-attack-out | No leakage test passes | [ ] |
| P4-U4 | Models: random forest, XGBoost, isolation forest, autoencoder, LSTM (optional graph model) | All evaluated on identical splits | [ ] |
| P4-U5 | Ablations: flow only, flow plus runtime, plus audit | Ablation table generated | [ ] |
| P4-U6 | Detection latency and overhead under load | CPU, memory, latency measured | [ ] |
| P4-U7 | Sanity check on CIC-IDS2017 or CSE-CIC-IDS2018 | Within range of published numbers or deviation explained | [ ] |
| P4-U8 | Short-lived EKS replication for generalization | Subset run, cluster destroyed, cost noted | [ ] |
| P4-U9 | Reproducibility: every number regenerates from tagged commits | Script regenerates all tables and figures | [ ] |
| P4-U10 | Paper 1 draft, arXiv preprint | Draft complete, references verified by hand | [ ] |
| P4-U11 | Phase 5 spec | `docs/specs/P5-ebpf.md` approved | [ ] |

Pivot rule: if baselines detect almost everything, focus on unknown attacks and false positives under benign changes. Never use random train/test splits.
**Gate G3:** Paper 1 contribution defensible, recorded in `ADR-G3`.

### P5: eBPF observability (Paper 2)

**Intent:** Low-overhead eBPF telemetry, and measured detection gain. Start only when P4 evaluation is stable.
**Spec:** `docs/specs/P5-ebpf.md`

| Unit | Description | Acceptance check | Status |
|---|---|---|---|
| P5-U1 | Learn eBPF: bpftrace exercises, Go with cilium/ebpf | Three working exercises committed | [ ] |
| P5-U2 | Survey Hubble, Tetragon, Pixie, Parca, Beyla | Comparison note, gap stated | [ ] |
| P5-U3 | Probe: per-pod TCP retransmits, connect latency, DNS latency, via cgroup id | Metrics attributed to correct pods | [ ] |
| P5-U4 | Prometheus exporter and DaemonSet on all nodes | Metrics scraped from all nodes | [ ] |
| P5-U5 | Feed probe features into P4 detectors | Feature table v2 | [ ] |
| P5-U6 | Overhead study vs sidecar and packet capture under k6 load | Results with environment documented | [ ] |
| P5-U7 | Ablation: detection gain from eBPF features | Reported honestly, including null result | [ ] |
| P5-U8 | Paper 2 draft (or section of Paper 1 if overlap is large) | Draft complete | [ ] |
| P5-U9 | Phase 6 spec | `docs/specs/P6-llm.md` approved | [ ] |

### P6: LLMs for cloud and network security (Paper 3)

**Intent:** LLM alert triage and policy synthesis, with safety evaluation. First to cut if effort runs short.
**Spec:** `docs/specs/P6-llm.md`

| Unit | Description | Acceptance check | Status |
|---|---|---|---|
| P6-U1 | Triage pipeline: Falco and Hubble events to incident summary and MITRE mapping | Runs end to end on sample events | [ ] |
| P6-U2 | Policy synthesis: CiliumNetworkPolicy from Hubble flows | Normal replay unbroken, attack replay blocked | [ ] |
| P6-U3 | Labeled incident set (100 to 200 events) and human review rubric | Set and rubric documented | [ ] |
| P6-U4 | Prompt-injection tests through log content, plus mitigations | Findings and tested mitigations recorded | [ ] |
| P6-U5 | Local model (Ollama) vs API model: accuracy, hallucination, latency, cost | Comparison table | [ ] |
| P6-U6 | Optional: misconfiguration detection for Terraform and Kubernetes manifests | Prototype and results | [ ] |
| P6-U7 | Paper 3 draft | Draft complete | [ ] |

Resource note: stop cluster VMs when running local models, or use a paid API.


## 4. Operations (cross-phase)

### Phase-exit checklist (Operations stage)

- [ ] Lab rebuilds from clean VMs with one command.
- [ ] All results regenerate from tagged commits.
- [ ] Experiment log complete: date, commit, config hash, dataset version, hypothesis, result, notes.
- [ ] ADRs written for major choices and the gate decision.
- [ ] `CLAUDE.md`, README and dataset card are current.
- [ ] Retrospective: what worked, what slipped, scope changes. Added to the phase spec.

### Standing practices

- Snapshot VMs before every attack run and every hardening change.
- Pin all versions (OS image, Kubernetes, Helm charts, container images).
- Never let the assistant produce experimental numbers or citations. Check each venue's AI-disclosure policy.
- Keep the Prometheus retention short and move bulky data off the laptop.

### Publication track

| Paper | Contribution | Ready after |
|---|---|---|
| 1 | Kubernetes security dataset and detection benchmark | G3 |
| 2 | eBPF features: detection gain vs overhead | P5 |
| 3 | LLM triage and policy synthesis, with prompt-injection risk | P6 |

Targets (verify current calls): workshops at IEEE CNS, ACM CCS, ACSAC, NOMS, NetSoft; journals IEEE Access, Computers & Security. Post every paper on arXiv.

### Application track (runs in parallel, not a phase)

- After P0: shortlist 8 to 10 professors, send a one-page summary and the repo link.
- Portfolio contents depend on how far the build has progressed: public repo, hardening report if done, literature matrix, written research plan. Do not promise a peer-reviewed paper before one exists.


## 5. Risk register

| Risk | Early signal | Response |
|---|---|---|
| Limited time | Unit stays open across many sessions | Shrink unit, cut P6, then P5 |
| Research gap not novel | G0 finds close prior work | Refine RQs before building |
| Dataset looks like a toy | Few attack classes, low variety | Multiple workloads, benign changes, repeated runs |
| RAM and disk limits | Swapping, VM OOM, disk over 80% | Online Boutique first, short retention, external disk |
| Hardening breaks cluster | Workloads fail after a control | One change at a time, snapshots, negative tests |
| Results not reproducible | Number without log entry | Experiment log, tags, pinned versions, checksums |
| Sensitive access mistakes | Work credentials on the machine | Isolated network, separate kubeconfig |
| Unverified AI claims | Citation or number from the assistant | Run experiments yourself, verify every reference |


## 6. Where to start

Begin with P0. Suggested order for the first bolts:

1. P0-U1: repo skeleton, then P0-U2 (`CLAUDE.md`) and P0-U3 (templates). These are the context files every later bolt depends on.
2. P0-U4 to P0-U6: libvirt, isolated network, base image. This is the first thing you run yourself.
3. P0-U7 and P0-U8 in parallel with any waiting time (image downloads, installs).
4. P0-U9 and P0-U10, then G0.

Next step: Mob Elaboration for P0. Claude drafts `docs/specs/P0-foundation.md` and the repo skeleton from the units above, and you review and approve before any build work starts.
