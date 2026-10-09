# Gap checklist (input for P0-U8 and G0)

Answer each question while reading, with the matrix ID that supports the answer. `?` means not yet known.

| # | Question | Answer | Evidence (matrix IDs) |
|---|---|---|---|
| 1 | Does any public dataset combine flow, runtime (syscall or eBPF) and Kubernetes audit signals for the same attack runs? | ? | |
| 2 | Do any datasets include benign operational changes (rollouts, autoscaling, node drain) as normal behaviour? | ? | |
| 3 | Are existing Kubernetes datasets collected on bare-metal clusters, or only on managed cloud or simulated setups? | ? | |
| 4 | Do existing studies compare ML detectors against rule baselines (Falco, Cilium verdicts) on identical splits? | ? | |
| 5 | Is the CPU, memory and latency overhead of eBPF feature extraction measured against packet capture or sidecars? | ? | |
| 6 | Have LLMs been evaluated on Kubernetes alert triage with attacker-controlled log content? | ? | |
| 7 | Has LLM-based synthesis of CiliumNetworkPolicy from Hubble flows been evaluated against attack replay? | ? | |
| 8 | Which attack classes are covered (container escape, lateral movement, cryptomining, DoS, credential theft)? | ? | |

G0 decision (recorded in `docs/adr/ADR-G0-literature-gap.md`): the gap is real if questions 1, 2 and at least one of 5 to 7 are answered "no existing work".
