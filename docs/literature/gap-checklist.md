# Gap checklist (input for P0-U8 and G0)

Answer each question while reading, with the matrix ID that supports the answer. Answers dated 2026-10-09 come from page abstracts only and are not exhaustive. "Not stated" means the page does not say, not that the work does not exist.

| # | Question | Answer | Evidence (matrix IDs) |
|---|---|---|---|
| 1 | Does any public dataset combine flow, runtime (syscall or eBPF) and Kubernetes audit signals for the same attack runs? | No source read combines flow, runtime and audit signals. Flow only: L01, L03, L24, L37. Resource metrics only: L04. Two types: L30 (syscalls and network events), L32 (syscalls, with flow features in the discussion). Syscalls only: L07, L09. Audit graph: L08. Data files of L01 and L04 not inspected. | |
| 2 | Do any datasets include benign operational changes (rollouts, autoscaling, node drain) as normal behaviour? | Not stated in any source read. L31 addresses concept drift in general, not Kubernetes rollouts or autoscaling. Unresolved. | |
| 3 | Are existing Kubernetes datasets collected on bare-metal clusters, or only on managed cloud or simulated setups? | Not stated for most sources. L24, L03 and L04 use VM or single-node setups; L19, L30 use kind; L32 uses Minikube. No source read uses a multi-node bare-metal cluster. This lab also uses VMs, so the claim is dropped (see G6). | |
| 4 | Do existing studies compare ML detectors against rule baselines (Falco, Cilium verdicts) on identical splits? | Not found. L27 compares an LLM with three rule-based tools, for static configuration only. L13 compares eBPF tools with each other. | |
| 5 | Is the CPU, memory and latency overhead of eBPF feature extraction measured against packet capture or sidecars? | L32 compares eBPF with perf for syscall monitoring (latency overhead by number of containers). L25 reports 0.014% overhead for eBPF flow tracking (Docker); L29 compares eBPF with a userspace detector. No comparison against packet capture or sidecars found. | |
| 6 | Have LLMs been evaluated on Kubernetes alert triage with attacker-controlled log content? | L20, L21, L22 test prompt injection through logs for SOC, cloud and network logs. L18 triages endpoint alerts and does not test attacker-controlled content. No Kubernetes-specific study found. | |
| 7 | Has LLM-based synthesis of CiliumNetworkPolicy from Hubble flows been evaluated against attack replay? | L19 generates NetworkPolicy from natural-language intent on Kind with Kindnet, not from observed flows and not on Cilium. Synthesis from Hubble flows evaluated against attack replay: not found. | |
| 8 | Which attack classes are covered (container escape, lateral movement, cryptomining, DoS, credential theft)? | Container escape (L07, L08, L09, L13), cryptomining and DoS (L13), cryptojacking (L32, L33, L04 simulation), lateral movement (L25, L26), brute force (L09), reverse shell and exfiltration (L30, L24). Credential theft not seen. | |

G0 decision (recorded in `docs/adr/ADR-G0-literature-gap.md`): the gap is real if questions 1, 2 and at least one of 5 to 7 are answered "no existing work".
