# Pinned kubescape inputs (P2-U1)

Kubescape normally downloads two settings from a remote portal on every scan. They can change without notice, which would move the scores between a baseline scan and a re-scan. Both are fixed here, so a re-scan differs only when the cluster differs.

| File | What it is | Source |
|---|---|---|
| `controls-config.json` | Thresholds and lists used by controls (allowed capabilities, label names, sensitive values and so on) | `kubescape download controls-config`, exported 2026-10-15 with kubescape v4.0.16, keys sorted |
| `exceptions.json` | Exceptions applied to findings. Empty on purpose | The default list has 298 entries (EKS and system components) and marks findings "w/exceptions"; the lab wants every finding reported |

The control definitions themselves are pinned by `KUBESCAPE_CONTROLS` in `infra/versions.env`. To update a file, re-export it, review the diff, and record the change in the P2 spec amendments.
