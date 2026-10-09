# Gap checklist (input for P0-U8 and G0)

Answer each question while reading, with the matrix ID that supports the answer. Answers dated 2026-10-09 come from page abstracts only and are not exhaustive. "Not stated" means the page does not say, not that the work does not exist.

| # | Question | Answer | Evidence (matrix IDs) |
|---|---|---|---|
| 1 | Does any public dataset combine flow, runtime (syscall or eBPF) and Kubernetes audit signals for the same attack runs? | No checked source combines flow, runtime and audit signals for the same attack runs. Flow only: L01, L03. Syscall and capabilities on Docker: L07. Audit graph on an edge device: L08. | |
| 2 | Do any datasets include benign operational changes (rollouts, autoscaling, node drain) as normal behaviour? | Not stated in any checked source. Unresolved. | |
| 3 | Are existing Kubernetes datasets collected on bare-metal clusters, or only on managed cloud or simulated setups? | Not stated on the checked pages (L13 setup not stated). Unresolved. | |
| 4 | Do existing studies compare ML detectors against rule baselines (Falco, Cilium verdicts) on identical splits? | Not found in checked sources. L13 compares eBPF tools with each other only; L02 names no baselines. | |
| 5 | Is the CPU, memory and latency overhead of eBPF feature extraction measured against packet capture or sidecars? | L13 reports CPU and memory per tool. No comparison against packet capture or sidecars seen. | |
| 6 | Have LLMs been evaluated on Kubernetes alert triage with attacker-controlled log content? | L20, L21, L22 test prompt injection through logs for SOC, cloud and network logs. None is Kubernetes-specific on the pages read. | |
| 7 | Has LLM-based synthesis of CiliumNetworkPolicy from Hubble flows been evaluated against attack replay? | Unresolved. L19 (NetPolAgent) was not readable. | |
| 8 | Which attack classes are covered (container escape, lateral movement, cryptomining, DoS, credential theft)? | Container escape (L07, L08, L13), cryptomining and DoS (L13). Lateral movement and credential theft not seen. | |

G0 decision (recorded in `docs/adr/ADR-G0-literature-gap.md`): the gap is real if questions 1, 2 and at least one of 5 to 7 are answered "no existing work".
