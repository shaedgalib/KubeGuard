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

1. Entries in `matrix.md` start as **leads** found by web search.
2. Each lead is checked against an official record: Crossref or DataCite for DOIs, the arXiv API for arXiv IDs, or the primary document when there is no identifier. The check covers title, authors, year and venue. Entries that match are marked `Verified` with the date. The evidence is in `docs/reports/P0-U7-verification.md`.
3. Reading level is recorded in `Check level` (abstract page or PDF pages read). The columns Data, Method, Attack coverage, Baselines and Limitations repeat what the pages read state. "Not stated" means the pages read did not say.
4. Theses, repositories, vendor blogs and documentation are marked in the `Venue / type` column. They may inform the review but do not count as papers.
5. Verification is metadata-level. A paper is read in full before it is cited. References enter `paper/refs.bib` only at that point.

## Search keywords used so far

Kubernetes intrusion detection dataset; Kubernetes anomaly detection audit logs; eBPF container runtime security overhead; Falco Tetragon Tracee comparison; microservice anomaly detection benchmark dataset; container escape syscall dataset; Cilium Hubble flow anomaly detection; LLM SOC alert triage; LLM Kubernetes network policy generation; prompt injection through logs.

Searches added on 2026-10-09: eBPF versus packet capture and sidecar overhead; concept drift and benign changes; LLM Kubernetes misconfiguration; lateral movement datasets; eBPF feature extraction for ML. Suggested next: graph models over service dependency graphs; LLM explanation of IDS alerts; Kubernetes audit-log datasets; Cilium and Hubble flow studies.

## Files

- [matrix.md](matrix.md): the literature matrix.
- [gap-checklist.md](gap-checklist.md): questions to answer while reading, input for P0-U8 and G0.
