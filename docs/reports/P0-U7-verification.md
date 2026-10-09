# P0-U7 evidence: metadata verification of literature entries

Date: 2026-10-09. Done by the assistant on the researcher's instruction.

Method: each entry was compared with the official record. DOIs were looked up in Crossref and DataCite, arXiv IDs through the arXiv API, and entries without an identifier were checked against the document itself or its host page. Compared fields: title, authors (surnames and order), year, venue.

Scope and limits: this confirms that the work exists and that the metadata are right. It does not assess quality, and it does not confirm the claims in the matrix columns Data, Method, Attack coverage, Baselines and Limitations beyond the pages and PDF pages recorded in the column "Check level". Read a paper before citing it.

Corrections found: L32 authors (Crossref order and spelling), L28 year (2026 per arXiv).

| ID | Title | Method | Result | Notes |
|---|---|---|---|---|
| L01 | AssureMOSS Kubernetes Run-time Monitoring Dataset | registry: DataCite | verified | Title, authors and year match the record |
| L02 | Method for Detecting Anomalies in Kubernetes Clusters Using LSTM Autoe | registry: Crossref (DOI only) | verified | DOI resolves in Crossref; Crossref has no author list, so authors come from the journal page |
| L03 | A Kubernetes dataset for misuse detection | registry: Crossref | verified | Title, authors and year match the record |
| L06 | Anomaly detection on system audit events | host page only | not counted | Host page only (university repository) |
| L07 | Docker Container Escape Attack Dataset: Capabilities and System Call T | registry: DataCite | verified | Title, authors and year match the record |
| L08 | Resource-Interaction Graph: Efficient Graph Representation for Anomaly | registry: arXiv API | verified | Title, authors and year match the record |
| L09 | A real-time intrusion detection system based on OC-SVM for containeriz | registry: Crossref | verified | Crossref match (surname particle "de Laat" differs only in splitting); PDF pp.1-6 also read |
| L10 | AnoMod: A Dataset for Anomaly Detection and Root Cause Analysis in Mic | host page only | not counted | Host page only (conference site) |
| L11 | Eadro: An End-to-End Troubleshooting Framework for Microservices on Mu | registry: arXiv API | verified | Title, authors and year match the record |
| L12 | A Scenario-Oriented Benchmark for Assessing AIOps Algorithms in Micros | registry: arXiv API | verified | Title, authors and year match the record |
| L13 | Comparative Analysis of eBPF-Based Runtime Security Monitoring Tools i | registry: Crossref | verified | Title, authors and year match the record |
| L14 | Leveraging eBPF for Enhanced Kubernetes Observability and Security | host page only | not counted | Host page only (university repository) |
| L16 | SecAlertBench: Evaluating Large Language Models for Tier-1 Alert Triag | host page only | not counted | GitHub README only; paper not located |
| L17 | Before You Hand Over the Wheel: Evaluating LLMs for Security Incident  | registry: arXiv API | verified | Title, authors and year match the record |
| L19 | A Self-Correcting Multi-Agent LLM Pipeline for Verified Kubernetes Net | primary document (PDF) | verified | Primary document read (PDF pp.1-6); no DOI or arXiv id |
| L20 | Poisoning the Watchtower: Prompt Injection Attacks Against LLM-Augment | registry: arXiv API | verified | Title, authors and year match the record |
| L21 | LogJack: Indirect Prompt Injection Through Cloud Logs Against LLM Debu | registry: arXiv API | verified | Title, authors and year match the record |
| L22 | Context Contamination in LLM Analysis of Network Security Logs: Poison | registry: arXiv API | verified | Title, authors and year match the record |
| L24 | Learning State Machines to Monitor and Detect Anomalies on a Kubernete | registry: arXiv API | verified | Title, authors and year match the record |
| L25 | Lateral Movement Identification in Cross-Cloud Deployment | primary document (PDF) | verified | Primary document read (PDF pp.1-4); no DOI or arXiv id |
| L26 | Inside Job: Defending Kubernetes Clusters Against Network Misconfigura | registry: arXiv API | verified | arXiv match (surname splitting differed only for "Di Francesco") |
| L27 | GenKubeSec: LLM-Based Kubernetes Misconfiguration Detection, Localizat | registry: arXiv API | verified | Title, authors and year match the record |
| L28 | Towards Secure Cloud-Native Computing: Unveiling Kubernetes Misconfigu | registry: arXiv API | verified | arXiv match; year 2026 per arXiv; page also names IEEE CLOUD 2025 |
| L29 | A flow-based IDS using Machine Learning in eBPF | registry: arXiv API | verified | Title, authors and year match the record |
| L30 | FedMon: Federated eBPF Monitoring for Distributed Anomaly Detection in | registry: arXiv API | verified | Title, authors and year match the record |
| L31 | METANOIA: A Lifelong Intrusion Detection and Investigation System for  | registry: arXiv API | verified | Title, authors and year match the record |
| L32 | Detecting Cryptojacking Containers Using eBPF-Based Security Runtime a | registry: Crossref | verified | Authors corrected to Crossref record |
| L33 | eBPF-based Cryptojacking Container Detection Framework in Kubernetes | host page only | not counted | Host page only (university repository) |

Result: 23 entries verified (target 15). Not counted: L06, L10, L14, L16, L33 (host page only). Not checked: L04, L05, L15, L18, L34, L35, L36.
