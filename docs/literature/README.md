# Literature review protocol (P0-U7)

Purpose: find out what already exists for the three research questions before the cluster is built (gate G0).

## Scope

| Area | Related RQ | Target |
|---|---|---|
| A. Kubernetes anomaly and intrusion detection, datasets | RQ1 | 5+ papers |
| B. eBPF observability and runtime security | RQ2 | 5+ papers |
| C. LLMs for security operations and policy synthesis | RQ3 | 5+ papers |

Acceptance check for P0-U7: 15 or more entries in `matrix.md` with `Verified = yes`.

## Rules

1. Entries in `matrix.md` start as **leads**, found by web search by the assistant. A lead has a title and a link taken from search results and nothing else. Authors, venue, year, results and quality are not known until the paper is opened.
2. The researcher opens every lead and records title, authors, venue, year and DOI or arXiv identifier in Zotero. Only then is `Verified` set to `yes` with the date.
3. Theses, repositories, vendor blogs and documentation are marked in the `Type` column. They may inform the review but do not count towards the 15 papers unless the researcher decides otherwise.
4. The assistant never writes claims about a paper's results into the matrix. The columns Data, Method, Attack coverage, Baselines and Limitations are filled by the researcher after reading.
5. References enter `paper/refs.bib` only after verification.

## Search keywords used so far

Kubernetes intrusion detection dataset; Kubernetes anomaly detection audit logs; eBPF container runtime security overhead; Falco Tetragon Tracee comparison; microservice anomaly detection benchmark dataset; container escape syscall dataset; Cilium Hubble flow anomaly detection; LLM SOC alert triage; LLM Kubernetes network policy generation; prompt injection through logs.

Suggested next searches: Kubernetes attack matrix and OWASP Kubernetes Top 10; CNI flow datasets; benign change datasets (rollouts, autoscaling); eBPF flow-feature extraction for ML; graph models over service dependency graphs; LLM explanation of IDS alerts.

## Zotero convention

Collection `KubeGuard` with sub-collections `A-k8s-detection`, `B-ebpf`, `C-llm`. Tags: `rq1`, `rq2`, `rq3`, `dataset`, `read`, `verified`. The library stays outside git. The citation key in the matrix is the Zotero key.

## Files

- [matrix.md](matrix.md): the literature matrix.
- [gap-checklist.md](gap-checklist.md): questions to answer while reading, input for P0-U8 and G0.
