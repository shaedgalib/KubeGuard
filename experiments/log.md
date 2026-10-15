# Experiment log

Every number in a paper must trace to an entry here.

| Date | Git commit | Config hash | Dataset version | Hypothesis | Result | Notes |
|---|---|---|---|---|---|---|
| 2026-10-09 | 623d253 | n/a | n/a | EXAMPLE ENTRY (format dry run, not an experiment) | n/a | Shows the expected columns. Replace or remove when the first real experiment is logged. |
| 2026-10-15 | 47f2ee2 | n/a | n/a | n/a (P2-U1 baseline measurement of the unhardened Phase 1 cluster, no hypothesis) | See docs/reports/P2-U1-baseline.md: scores as printed by kube-bench v0.16.0 (cis-1.12) and kubescape v4.0.16, copied by script | Raw scan files outside git: baseline-20261015-235444 (checksums in the report) |
| 2026-10-16 | 7a0f384 | n/a | n/a | P2-U2 and P2-U6: the Ansible role `hardening` fixes the kube-bench FAIL and WARN checks and kubescape controls marked Fix in the triage, and encrypts Secrets in etcd and writes an audit log | See docs/reports/P2-U2-cis-fixes.md (scan comparison, copied by script from kube-bench v0.16.0 cis-1.12 and kubescape v4.0.16) and docs/reports/P2-U6-encryption-audit-evidence.md (test, evidence and drill output) | Raw scan files outside git: after-hardening-20261016-011514 (checksums in the U2 report); superseded first scan after-u2-u6-20261016-011143 (stray test namespace, see the report). Scan context records uncommitted changes (test cleanup fix, evidence script) that the scanners do not use |
