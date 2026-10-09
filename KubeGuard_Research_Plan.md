# KubeGuard

**From Network Anomaly Detection to Cloud-Native Security: Intrusion Detection, eBPF Observability and LLM-Assisted Defense on Bare-Metal Kubernetes**

Research plan and working document. Author: Shaed Shad Ullah Galib. Version 1.0, 8 October 2026.


## 1. Overview

KubeGuard extends your undergraduate NetGuard project (network performance monitoring and ML anomaly detection) into a postgraduate research programme on cloud-native security. You build a bare-metal Kubernetes lab, harden it, generate a labeled dataset of attacks, build detection on top of it, add eBPF-based observability, and finally use LLMs to triage and explain what the detectors find.


### Goal

- Build a research portfolio for MS/PhD applications in network and cloud security: a reproducible lab, a public dataset, and up to three papers.
- Grow from classic network anomaly detection (NetGuard) to cloud-native security, using your DevOps experience as a differentiator.


### Candidate research questions (draft v0, to be refined after the Phase 0 literature scan)

- RQ1: How well do flow-level, runtime-level and audit-level signals detect attacks in a bare-metal Kubernetes cluster, compared with rule-based baselines (Falco rules, Cilium policy verdicts)?
- RQ2: How much detection quality do eBPF-derived features add, and at what CPU, memory and latency overhead compared with packet capture or sidecars?
- RQ3: Can LLMs triage alerts and synthesise network policies from observed flows accurately and safely, given that logs are attacker-controlled input?


### Assumptions and constraints

- About 10 to 12 hours per week alongside a full-time job.
- Hardware: HP EliteBook 845 G11, Ryzen 7 8840HS (8 cores, 16 threads), 32 GB RAM, 512 GB disk, Ubuntu 24.04. Three KVM VMs host the cluster.
- All attack work runs in an isolated lab network. No work credentials or client environments are used.
- Dates below are indicative, counted from 8 October 2026. Venue deadlines must be re-checked against current calls for papers.


### How the phases connect

| Phase | Produces | Used by |
|---|---|---|
| 1. Cluster and networking | kubeadm cluster with Cilium and Hubble | All later phases |
| 2. Hardening | Security baseline with before/after scores | Phase 3 attack target; Paper 1 context |
| 3. Workload, attacks, data | Labeled dataset v0.1 and collection pipeline | Phase 4 training and evaluation |
| 4. Intrusion detection | Detectors and benchmark results | Phase 5 comparison; Phase 6 input |
| 5. eBPF observability | Low-overhead flow and event features | Improves Phase 4; feeds Phase 6 |
| 6. LLMs for security | Alert triage and policy synthesis | Consumes Phase 4 and 5 outputs |


## 2. Roadmap and milestones

| Phase | Weeks (dates) | Focus | Main output |
|---|---|---|---|
| 0 | 1 (8-14 Oct) | Lab, repo, literature scan | Repo, literature matrix, RQ v0 |
| 1 | 2-5 (15 Oct-11 Nov) | Bare-metal cluster and networking | One-command cluster rebuild |
| 2 | 6-9 (12 Nov-9 Dec) | Security hardening | Hardening report v1 |
| 3 | 10-13 (10 Dec-6 Jan) | Workload, attacks, data pipeline | Dataset v0.1 |
| 4 | 14-22 (7 Jan-10 Mar) | Intrusion detection | Paper 1 draft, arXiv |
| 5 | 20-30 (18 Feb-5 May) | eBPF observability | Paper 2 draft |
| 6 | 28-40 (15 Apr-7 Jul) | LLMs for security | Paper 3 draft |


### Decision gates

- G0 (end of Phase 0): literature scan shows a genuine gap. If not, adjust the research questions before building.
- G1 (end of Phase 2): cluster is stable and reproducible. If not, fix before generating any data.
- G2 (end of Phase 3): dataset has enough normal and attack coverage, and baselines do not already solve it. If they do, shift the angle to unknown attacks or false positives under benign changes (rollouts, autoscaling).
- G3 (end of Phase 4): Paper 1 has a defensible contribution. Cut Phase 6 first if time runs short; keep Phases 1 to 4.


## 3. Working method (AIDLC adapted for research)


### Lifecycle

- Inception: each phase starts with a short spec (objective, hypothesis, metrics, scope) saved in docs/specs/.
- Construction: break the phase into small units of work, each with an acceptance check. Commit often, tag each experiment.
- Operations: end every phase with a reproducibility check: the lab rebuilds and results regenerate from the repo.


### Repository structure

- docs/specs/ : one spec per phase.
- docs/adr/ : architecture decision records, one short file per major choice (why Cilium, why Falco).
- docs/dataset-card.md : how data was collected, labeled, and its limits.
- infra/ : Ansible roles, libvirt/Vagrant or Terraform definitions, Makefile (make up, make down, make reset).
- k8s/ : manifests, Helm values, Cilium and Kyverno policies.
- attacks/ : scripted attack scenarios and the attack manifest generator.
- collect/ : data collection and Parquet export pipeline.
- ml/ : features, models, evaluation code. experiments/ : experiment log and configs.
- paper/ : LaTeX sources and figures. CLAUDE.md : conventions for the AI assistant.


### Experiment log fields

Date, git commit, config hash, dataset version, hypothesis, result, notes. Every number in a paper must trace to a log entry.


### Rules for using Claude in VS Code

- Use a separate kubeconfig and no work AWS or client credentials on this machine or profile.
- Run attacks only inside the isolated libvirt network. Snapshot VMs before every attack run.
- Write the core parts yourself first (cluster setup, network policies, detection logic). Use the assistant for Ansible, scripts, tests, pipeline code and drafting docs.
- Never let the assistant produce experimental numbers or citations. Run experiments yourself and verify every reference. Check each venue's policy on AI-assistance disclosure.
- Keep CLAUDE.md up to date with the lab rules, directory layout and commands.


### Weekly rhythm

- Two evening build sessions, one evening of paper reading (two papers a week), one weekend block for the main task.
- Sunday: 30-minute review of what was planned, what was done, and what changes. Update the experiment log and ADRs.


## Phase 0: Lab, repository and literature scan

Timing: Week 1 (8-14 October 2026)

Objective: Prepare the lab and the repo, and confirm the research gap before building.


### Tasks

- [ ] Install KVM/libvirt and verify virtualization. Create an isolated libvirt network with no route to your home or office LAN.
- [ ] Download Ubuntu 24.04 cloud images and plan VM sizes: control plane 4 GB, two workers 8 GB each.
- [ ] Create the GitHub repo with the structure in section 3, a README, a Makefile skeleton and CLAUDE.md.
- [ ] Set up a literature matrix (paper, data, method, attack coverage, limitations).
- [ ] Read at least 15 papers across Kubernetes anomaly detection, eBPF observability and LLMs for security operations.
- [ ] Write research questions v0 and the spec for Phase 1.
- [ ] Decide on the AWS certification renewals and whether to pursue CKS (side track).


### Deliverables

- Running isolated lab network and base VM images.
- Repository with CLAUDE.md and spec template.
- Literature matrix with 15 or more entries.
- Research questions v0.


### Done when

- VMs boot and can reach each other but not your home LAN.
- Gate G0 decision is written down in docs/adr/.


### Risks and notes

- The literature may already cover your idea. Treat this as input to refine the angle, not as a reason to stop.


## Phase 1: Bare-metal Kubernetes cluster and networking

Timing: Weeks 2-5 (15 October - 11 November 2026)

Objective: Build a reproducible kubeadm cluster with Cilium and Hubble, and understand every layer you are running.


### Tasks

- [ ] Build three VMs (control plane, two workers) from cloud-init.
- [ ] Write Ansible roles: common setup (swap off, kernel modules, sysctl), containerd, kubeadm init and join.
- [ ] Install Cilium with kube-proxy replacement. Enable Hubble relay and UI.
- [ ] Add MetalLB (L2 address pool), an ingress controller or Cilium Gateway API, and local-path storage.
- [ ] Install kube-prometheus-stack for baseline monitoring.
- [ ] Practice an etcd snapshot and restore drill. Practice a node drain, a node failure and a rejoin.
- [ ] Deploy a sample app, expose it via MetalLB and ingress, and view its flows in Hubble.
- [ ] Wire everything behind make up, make down and make reset. Write ADRs for each major choice.
- [ ] Study alongside: Kubernetes The Hard Way, the CKA curriculum, and Cilium's free labs.


### Deliverables

- Repo that rebuilds the whole cluster with one command.
- Working Hubble flow view and Prometheus/Grafana dashboards.
- ADRs for CNI, load balancer, ingress and storage choices.


### Done when

- From clean VMs, make cluster produces a Ready cluster with Hubble flows visible.
- etcd restore has been tested successfully.
- Rebuild time is documented (target under 40 minutes).


### Risks and notes

- RAM is tight with 12 GB left for the host. Keep Prometheus retention short.
- Ensure the guest kernel has BTF (Ubuntu 24.04 does) so eBPF works later.


## Phase 2: Security hardening

Timing: Weeks 6-9 (12 November - 9 December 2026)

Objective: Harden the cluster measurably and document each control. This becomes the baseline for the attack and detection work.


### Tasks

- [ ] Run kube-bench (CIS benchmark) and kubescape. Record the baseline scores before changing anything.
- [ ] Fix findings one by one: kubelet authentication, anonymous access, file permissions, API server flags.
- [ ] Audit RBAC and reduce it to least privilege. Enforce Pod Security Admission at the restricted level.
- [ ] Apply default-deny CiliumNetworkPolicy per namespace, then add explicit allow rules.
- [ ] Enable etcd encryption at rest and an API server audit policy with log rotation.
- [ ] Install Kyverno and write policies (no privileged pods, resource limits required, image registry allowlist).
- [ ] Enable service-to-service mTLS (Cilium mutual auth, Istio ambient or Linkerd, whichever you choose).
- [ ] Add image scanning with Trivy and a simple secrets workflow (SOPS or External Secrets).
- [ ] Write negative tests: show that each control actually blocks the bad action.
- [ ] Produce a table mapping each control to its EKS equivalent (IRSA, GuardDuty, managed control plane).


### Deliverables

- Hardening report v1 with before/after benchmark scores.
- Policies stored under k8s/ with negative tests.
- Control-to-EKS mapping table.


### Done when

- Benchmark score improvement is documented and reproducible.
- Every policy has at least one passing negative test.
- Gate G1: cluster is stable after hardening.


### Risks and notes

- Hardening can break workloads. Apply controls incrementally and keep snapshots.
- Optional: CKS certification preparation fits this phase well.


## Phase 3: Workload, attacks and data pipeline

Timing: Weeks 10-13 (10 December 2026 - 6 January 2027)

Objective: Create realistic normal traffic, scripted attacks with ground-truth labels, and a repeatable collection pipeline.


### Tasks

- [ ] Deploy Online Boutique first. Add Train Ticket later if RAM allows.
- [ ] Generate normal traffic with k6 or Locust. Include varied profiles: idle, steady, burst, and benign changes such as rolling updates and autoscaling.
- [ ] Script attacks: port scans, lateral movement between pods, DoS, crypto-miner container, DNS tunneling, data exfiltration, API server abuse, and Kubernetes Goat scenarios. Map each to MITRE ATT&CK for Containers.
- [ ] Build an attack runner that writes an attack manifest (attack id, type, start, end, source and target pods) for every run.
- [ ] Collect Hubble flow exports, Falco runtime events, API audit logs and Prometheus metrics. Optionally add Zeek or Suricata on a node.
- [ ] Define a schema and export to Parquet with checksums. Write the dataset card.
- [ ] Repeat each attack at least 10 times with varied parameters.
- [ ] Snapshot VMs before each attack session and reset after.


### Deliverables

- Dataset v0.1 and the collection pipeline, both public on GitHub.
- Dataset card documenting collection, labeling and limits.
- Attack catalogue with MITRE mapping.


### Done when

- At least 72 hours of aggregated normal traffic and at least 6 attack classes with 10 or more runs each.
- The pipeline replays from the repo.
- Gate G2 decision recorded.


### Risks and notes

- Disk: 512 GB is shared. Move raw pcaps to an external drive and keep only features in the repo.
- Document ethics: isolated lab, no real targets.


## Phase 4: Intrusion detection

Timing: Weeks 14-22 (7 January - 10 March 2027)

Objective: Detect the Phase 3 attacks and benchmark against realistic baselines. This is Paper 1.


### Tasks

- [ ] Implement baselines first: Falco default rules, Suricata rules (if used) and Cilium policy verdicts.
- [ ] Engineer features per signal source (flow, runtime, audit, metrics) and build feature windows.
- [ ] Train models: random forest, XGBoost, isolation forest, autoencoder, LSTM. Optional: graph model over the service dependency graph.
- [ ] Evaluate with time-based splits, leave-one-attack-out for unknown attacks, and ablations (flow only, flow plus runtime, plus audit).
- [ ] Measure detection latency and overhead (CPU and memory) under load.
- [ ] Sanity-check the pipeline on CIC-IDS2017 or CSE-CIC-IDS2018 against published numbers.
- [ ] Replicate a subset on an EKS cluster for a generalization check, keeping it short-lived to control cost.
- [ ] Write Paper 1 (dataset and benchmark) and post it on arXiv.


### Deliverables

- Reproducible detection code and evaluation harness.
- Results tables and figures traceable to the experiment log.
- Paper 1 draft and arXiv preprint.


### Done when

- All reported numbers regenerate from tagged commits.
- Baselines and ML models are compared on the same splits.
- Gate G3 decision recorded.


### Risks and notes

- If baselines already detect almost everything, pivot to unknown attacks and false positives under benign changes.
- Avoid random train/test splits: they leak and reviewers will notice.


## Phase 5: eBPF observability

Timing: Weeks 20-30 (18 February - 5 May 2027)

Objective: Build low-overhead eBPF telemetry and measure what it adds to detection. This is Paper 2, or a major section of Paper 1 if the overlap is large.


### Tasks

- [ ] Learn eBPF: bpftrace exercises first, then Go with the cilium/ebpf library. Reference: Liz Rice, Learning eBPF.
- [ ] Study Hubble, Tetragon, Pixie, Parca and Grafana Beyla to understand what already exists.
- [ ] Build a small custom probe: per-pod TCP retransmits, connect latency and DNS latency, attributed to pods via cgroup id.
- [ ] Export probe metrics to Prometheus and feed them into the Phase 4 detectors.
- [ ] Measure overhead and request latency impact against a sidecar approach and against packet capture, using k6 load.
- [ ] Evaluate detection gain from eBPF features through an ablation study.
- [ ] Write Paper 2.


### Deliverables

- Working eBPF probe running on all nodes.
- Overhead comparison results.
- Paper 2 draft.


### Done when

- Probe overhead is measured under load and documented.
- Detection gain (or lack of it) is reported honestly with an ablation.


### Risks and notes

- Kernel and BTF compatibility, and VM virtualization overhead, can distort measurements. Document the environment precisely.
- This phase overlaps with Phase 4. Do not start it before Phase 4 evaluation is stable.


## Phase 6: LLMs for cloud and network security

Timing: Weeks 28-40 (15 April - 7 July 2027)

Objective: Use LLMs to triage alerts and synthesise network policies from observed flows, with attention to safety. This is Paper 3.


### Tasks

- [ ] Build an alert triage pipeline: feed Falco and Hubble events to an LLM that summarises the incident and maps it to MITRE techniques.
- [ ] Build policy synthesis: generate CiliumNetworkPolicy from observed Hubble flows, then validate by replaying normal traffic (nothing breaks) and attack traffic (attack is blocked).
- [ ] Optionally add misconfiguration detection for Terraform and Kubernetes manifests.
- [ ] Test prompt injection through log content, since logs are attacker-controlled text.
- [ ] Create an evaluation set of 100 to 200 labeled incident events with a human review rubric.
- [ ] Compare a local model (via Ollama) with an API model on accuracy, hallucination rate, latency and cost.
- [ ] Write Paper 3.


### Deliverables

- Evaluation harness and labeled incident set.
- Triage and policy synthesis prototypes.
- Paper 3 draft.


### Done when

- Results are reproducible and the evaluation set is documented.
- Prompt injection findings are reported, with mitigations tested.


### Risks and notes

- Local CPU inference is slow and the integrated GPU has poor ML support. Stop cluster VMs while running local models, or use a paid API.
- This is the first phase to cut if time is short.


## 4. Application and publication strategy


### What will exist at application time

Fall 2027 deadlines for US programmes are typically around December 2026 to January 2027. Counted from 8 October, you will have finished Phases 0 and 1 and be in the middle of Phase 2 by early December, and in Phase 3 by January. So the portfolio at application time will be:

- A public GitHub repo with a reproducible bare-metal Kubernetes lab and ADRs.
- A hardening report (if Phase 2 finishes early) or a work-in-progress version.
- The literature matrix, a written research plan and a clear statement of purpose built on the NetGuard to KubeGuard story.
- No peer-reviewed paper yet. Do not promise one in your applications; describe the work as in progress.

To improve the odds, consider compressing Phase 1 into 3 weeks if you can, and finishing Phase 2 before the early deadlines. Many European and Canadian positions run on rolling deadlines, which fits this timeline better.


### Target venues (verify current calls for papers)

- Workshops attached to IEEE CNS, ACM CCS (for example cloud security), ACSAC, NOMS and NetSoft are realistic first targets.
- Journals: IEEE Access and Computers & Security are accessible; Journal of Network and Computer Applications has a higher bar.
- Post every paper on arXiv. Offer your code and dataset for artifact evaluation where venues support it.


### Papers

| Paper | Contribution | Depends on |
|---|---|---|
| 1 | Kubernetes security dataset and detection benchmark | Phases 1-4 |
| 2 | eBPF-derived features: detection gain versus overhead | Phases 4-5 |
| 3 | LLM alert triage and policy synthesis, with prompt-injection risk | Phases 4-6 |


### Outreach

- Shortlist 8 to 10 professors in network security and cloud security after the Phase 0 literature scan.
- Email each with a one-page summary and the repo link, not just your CV.


## 5. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Limited time (full-time job) | Fixed weekly rhythm. If a phase slips, cut Phase 6 first and keep Phases 1-4. |
| Research gap is not novel | Phase 0 literature scan and Gate G0. Refine research questions before building. |
| Dataset looks like a toy lab | Multiple workloads, 6+ attack classes, benign changes, repeated runs, public dataset card. |
| RAM and disk limits on the laptop | Online Boutique first, short retention, external disk for pcaps, stop VMs for local LLM runs. |
| Hardening breaks the cluster | Incremental changes, snapshots, negative tests, and a one-command rebuild. |
| Results cannot be reproduced | Experiment log, tagged commits, pinned versions, dataset checksums. |
| Mistakes with sensitive access | Isolated network, separate kubeconfig, no work credentials on this machine. |
| Unverified AI-generated claims | Run experiments yourself, verify every reference, follow venue AI-disclosure policy. |


## 6. Resources

- Kubernetes: Kubernetes The Hard Way, CKA and CKS curricula, kubeadm documentation.
- Cilium and Hubble documentation and Isovalent free labs.
- eBPF: Liz Rice, Learning eBPF; cilium/ebpf Go library; bpftrace documentation.
- Attacks and benchmarks: Kubernetes Goat, kube-hunter, MITRE ATT&CK for Containers, Online Boutique, Train Ticket.
- Datasets for sanity checks: CIC-IDS2017, CSE-CIC-IDS2018, UNSW-NB15.
- Tools: Falco, Tetragon, Kyverno, Trivy, kube-bench, kubescape, Prometheus, Grafana, Zeek, Suricata, Ollama, scikit-learn, PyTorch.


## 7. First week checklist

- [ ] Install KVM/libvirt and create the isolated network.
- [ ] Create the GitHub repo with the structure from section 3.
- [ ] Write CLAUDE.md with the lab rules and commands.
- [ ] Start the literature matrix (target 5 papers this week).
- [ ] Write the Phase 1 spec in docs/specs/.
- [ ] Create base Ubuntu 24.04 VM images and snapshot them.

