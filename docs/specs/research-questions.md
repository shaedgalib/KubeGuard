# Research questions v0 and gap analysis (P0-U8)

Status: draft, pending approval
Approved by / date:

Sources: the programme plan ([docs/AIDLC_Master_Plan.md](../AIDLC_Master_Plan.md)) and the literature matrix ([docs/literature/matrix.md](../literature/matrix.md), IDs `L01` to `L36`). Evidence statements below come from the abstracts and the PDF pages recorded in the matrix column "Check level". "Not stated" means the pages read did not say, not that the work does not exist. This document contains no experimental results.

## 1. Problem statement

Kubernetes clusters run many short-lived workloads, so normal behaviour changes constantly through rollouts, autoscaling and node maintenance. Published detectors and datasets for Kubernetes security mostly use one signal type, such as network flows or system calls, and rarely state how benign operational changes are handled. This project builds a labelled dataset on a self-hosted lab cluster that combines flow, runtime and audit signals with benign changes included, evaluates detectors against rule-based baselines, measures the cost of eBPF-based collection, and tests whether LLMs can triage alerts safely when the logs they read are attacker-controlled.

## 2. Research questions

| ID | Question | Outcome measures (names only, values come from experiments) |
|---|---|---|
| RQ1 | How well do flow-, runtime- and audit-level signals, alone and combined, detect attacks in a self-hosted Kubernetes cluster, compared with rule baselines (Falco, Cilium verdicts), and how many false alarms do benign rollouts and autoscaling cause? | Precision, recall, F1 per attack class; false positives per benign-change type; time to detect; identical train and test splits for all detectors |
| RQ2 | What do eBPF-derived features add over packet capture or sidecar-based collection, and at what CPU, memory and latency overhead? | Detection quality with and without eBPF features; CPU, memory and added request latency per node |
| RQ3 | Can LLMs triage alerts and synthesise CiliumNetworkPolicy from observed Hubble flows accurately and safely, given that log content is attacker-controlled? | Triage accuracy and hallucination rate; injection success rate under attacker-written log fields; policy correctness by connectivity test and attack replay |

Sub-questions (draft):
- RQ1a: Which signal combination is best per attack class?
- RQ1b: Does adding audit logs change detection beyond flow plus runtime?
- RQ2a: Is the overhead of eBPF collection acceptable at the cluster sizes of this lab (three nodes)? Results at this scale must not be generalised beyond it.
- RQ3a: Which defences against log-borne prompt injection hold up in this setting?

## 3. Gap analysis

Strength: **strong** = several checked sources point the same way and none contradicts; **moderate** = checked sources point the same way, coverage incomplete; **weak** = few sources, or the search may be the limit.

| # | Claimed gap | What existing work covers (matrix IDs) | What remains open | Strength |
|---|---|---|---|---|
| G1 | No public dataset combines flow, runtime and audit signals from the same Kubernetes attack runs, with benign operational changes | Full texts read for L24 and L01 (NetFlow only), L03 (tcpdump flows only), L30 and L32; the L04 page was read. Flow only: L01, L24, L37 (NetFlow, VM testbed with Calico; Elastic Beats including Auditbeat were deployed but only NetFlow is used; benign = 30 simulated users) and L03 (10 CVE-based attacks). Resource metrics only: L04 (CPU, memory and disk I/O collected with Prometheus on a single-node Docker-based cluster; normal mode with benign workload fluctuations versus attack mode). Two signal types: L30 (eBPF syscalls and network events, kind clusters on one host, three attacks, no dataset release stated) and L32 (Tetragon syscalls used for detection, flow features shown in the discussion only, cryptojacking only, single-node Minikube, benign = benchmark workloads, dataset on request). Syscalls only, on Docker: L07, L09. Audit graph on an edge device: L08. No source read treats rollouts, autoscaling or node maintenance as benign change or uses Kubernetes audit logs | Three signal types for the same runs; several attack classes; benign operational changes labelled as normal | Moderate to strong (six sources read in full or by page; data files of L01 and L04 not inspected; others abstract level) |
| G2 | Detectors are rarely compared with rule baselines on identical splits | L24 compares only with Isolation Forest; L03 uses a one-class SVM with no other baseline; L30 compares with isolated and centralised versions of itself; L13 compares eBPF tools with each other. None compares an ML detector with Falco or Cilium verdicts. L27 compares an LLM with rule tools for static configuration only | ML detectors versus Falco and Cilium verdicts at runtime on the same data | Moderate |
| G3 | The cost of eBPF-based feature collection is not compared with packet capture or sidecars on Kubernetes | L32 compares eBPF (Tetragon) with perf for syscall monitoring as the number of monitored containers grows (single-node Minikube, MariaDB) and reports latency overhead per workload. L25 reports overhead of eBPF flow tracking on Docker. L29 compares eBPF with a userspace implementation of one detector. L13 reports CPU and memory per tool. No source read compares eBPF collection with packet capture or sidecars in a cluster. Only blog posts turned up for that comparison, so it may be a search gap | A like-for-like comparison of eBPF collection with packet capture and sidecars in a cluster, on more than one node | Weak to moderate (eBPF versus perf is covered by L32; packet capture and sidecars are not) |
| G4 | LLM alert triage under attacker-controlled logs has not been studied for Kubernetes | Triage benchmarks and studies: L16, L17, L18 (thesis: five LLMs on 58 Wazuh endpoint alerts, no Kubernetes, attacker-controlled content not tested, single run). Log-borne prompt injection in SOC, cloud and network logs: L20, L21, L22. None is Kubernetes-specific in the pages read | Kubernetes alerts (audit, runtime, flow) with attacker-writable fields such as pod names, labels and request URIs | Moderate |
| G5 | Policy synthesis from observed flows, evaluated by attack replay, is not covered | L19 generates NetworkPolicy from natural-language intent on Kind with Kindnet; L27, L28 and L34 (a registered report on Helm charts) cover static configuration review. None starts from observed flows or targets Cilium | CiliumNetworkPolicy from Hubble flows, scored by normal replay (unbroken) and attack replay (blocked) | Weak to moderate |
| G6 | (Dropped) "Bare-metal" as a gap | L24 and L03 use VM-based self-hosted clusters like this lab, and L30 uses kind. This lab also runs in KVM virtual machines on one host, so it cannot claim bare-metal data. Use "self-hosted lab cluster" instead | Nothing to claim | Dropped |

## 4. Threats to the gap analysis

- The scan used web search and abstract-level reading. Sections not read (results, limitations) could contradict a gap.
- Four leads were not checked (L05, L15, L35, L36). The data files of L01 (repository maintenance until about 11 October 2026) and L04 were not inspected, and the dataset of L32 is available on request only.
- Several sources are arXiv preprints with no venue stated. Their claims are unreviewed.
- The search was in English and limited to what the search tool returned.
- Venues and datasets from 2026 may not be indexed yet.

## 5. Scope and non-goals

In scope: a three-node VM-based lab on libvirt (KVM guests on one host), one microservice benchmark first (Online Boutique), a fixed set of attack classes, benign changes, detectors, eBPF collection, and LLM triage and policy synthesis on lab data.

Out of scope: production deployments, managed cloud clusters, new exploit development beyond standard lab attacks, detectors for service-mesh traffic, claims beyond the three-node scale.

## 6. Gate G0 proposal (decision belongs to the researcher)

Proposed pass rule: G1 holds after the closest sources are read in full and none provides the three signal types with benign changes, and at least one of G3, G4 or G5 also holds.

Status on 2026-10-09: L01 (documentation), L03, L24, L30 and L32 were read in full and the L04 page was read; none meets the G1 test. G1 is supported. Remaining uncertainty: the data files of L01 and L04, and four unchecked leads.

If G1 does not hold: shift the angle to false positives under benign changes (the fallback in the programme plan) and revise RQ1.
If only G1 holds: proceed, with RQ2 and RQ3 reduced in scope.

The decision and its evidence are recorded in `docs/adr/ADR-G0-literature-gap.md` after approval.

## 7. Decisions needed from the researcher

1. Are the three RQs, with their sub-questions, the right wording and scope?
2. Do you accept the proposed G0 pass rule, or replace it?
3. Is the order of attack classes and the benchmark workload fixed here, or left to the Phase 3 spec?
4. G6 is dropped (this lab is VM-based, so "bare-metal" is not a claim). Keep G2 as a claim?
