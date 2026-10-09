# Gap checklist (input for P0-U8 and G0)

Answer each question while reading, with the matrix ID that supports the answer. Answers dated 2026-10-09 come from page abstracts only and are not exhaustive. "Not stated" means the page does not say, not that the work does not exist.

| # | Question | Answer | Evidence (matrix IDs) |
|---|---|---|---|
| 1 | Does any public dataset combine flow, runtime (syscall or eBPF) and Kubernetes audit signals for the same attack runs? | Partial. L30 (syscalls and network events, three Kubernetes clusters, attack types not stated) and L32 (Tetragon syscalls plus flow-level data, cryptojacking only) combine two signal types. No source read adds Kubernetes audit logs or covers several attack classes. Flow only: L01, L03, L24. Syscalls only: L07, L09. Audit graph: L08. | |
| 2 | Do any datasets include benign operational changes (rollouts, autoscaling, node drain) as normal behaviour? | Not stated in any source read. L31 addresses concept drift in general, not Kubernetes rollouts or autoscaling. Unresolved. | |
| 3 | Are existing Kubernetes datasets collected on bare-metal clusters, or only on managed cloud or simulated setups? | Not stated for most sources. L19 uses Kind (Kubernetes in Docker); L09 and L25 use Docker, not Kubernetes. Unresolved. | |
| 4 | Do existing studies compare ML detectors against rule baselines (Falco, Cilium verdicts) on identical splits? | Not found. L27 compares an LLM with three rule-based tools, for static configuration only. L13 compares eBPF tools with each other. | |
| 5 | Is the CPU, memory and latency overhead of eBPF feature extraction measured against packet capture or sidecars? | No comparison against packet capture or sidecars found. L25 reports 0.014% overhead for eBPF flow tracking (Docker); L29 compares eBPF with a userspace detector; L13 reports CPU and memory per tool. | |
| 6 | Have LLMs been evaluated on Kubernetes alert triage with attacker-controlled log content? | L20, L21, L22 test prompt injection through logs for SOC, cloud and network logs. L22 (PDF pp. 1-8) does not mention Kubernetes. No Kubernetes-specific study found yet. | |
| 7 | Has LLM-based synthesis of CiliumNetworkPolicy from Hubble flows been evaluated against attack replay? | L19 generates NetworkPolicy from natural-language intent on Kind with Kindnet, not from observed flows and not on Cilium. Synthesis from Hubble flows evaluated against attack replay: not found. | |
| 8 | Which attack classes are covered (container escape, lateral movement, cryptomining, DoS, credential theft)? | Container escape (L07, L08, L09, L13), cryptomining and DoS (L13), cryptojacking (L32, L33), lateral movement (L25, L26), brute force (L09). Credential theft not seen. | |

G0 decision (recorded in `docs/adr/ADR-G0-literature-gap.md`): the gap is real if questions 1, 2 and at least one of 5 to 7 are answered "no existing work".
