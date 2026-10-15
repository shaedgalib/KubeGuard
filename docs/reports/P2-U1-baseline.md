# P2-U1 evidence: baseline scans before any hardening

Date: 2026-10-15. Branch: `feat/p2-baseline-hardening`. Cluster: Kubernetes 1.36.5, three nodes (`kg-control-1`, `kg-worker-1`, `kg-worker-2`), exactly as left at the end of Phase 1 (`p1-done`). Scanner tooling: commit `47f2ee2` (`infra/scans/`, `k8s/scanners/`).

The scans were started with `make scan LABEL=baseline` from the researcher's terminal session, by the assistant at the researcher's instruction ("complete by yourself"). The assistant did not produce any number: every figure below is printed by `infra/scans/summarize.py` from the scanners' own JSON, and the section "Results" is that output unchanged (headings moved down one level). Nothing in the cluster was changed before the scan except what the scan itself adds (see "What the scan changed").

## How the scans were run

| Item | Value |
|---|---|
| kube-bench | v0.16.0, image `docker.io/aquasec/kube-bench:v0.16.0`, profile `cis-1.12` set by hand |
| kube-bench targets | control-plane node: `master,etcd,controlplane,policies,node`; each worker: `node` |
| kube-bench method | Jobs in namespace `scanners` (`hostPID`, read-only host paths, no API token), logs saved, Jobs deleted |
| kubescape | v4.0.16 from the host, project kubeconfig only, `--keep-local`, `--host-scan=false` (nothing is deployed in the cluster, nothing is submitted) |
| kubescape frameworks | `nsa`, `mitre`, `cis-v1.12.0` |
| kubescape inputs | controls from regolibrary `v2.0.38`; `infra/scans/kubescape/controls-config.json` and an empty `exceptions.json`, both in the repository |
| Profiles chosen by | the assistant (the unit plan leaves the choice to the researcher); change them in `infra/versions.env` and `infra/scans/run.sh` |

Raw output is kept outside git in `~/.local/share/kubeguard/scans/baseline-20261015-235444/` (directory mode 700). Checksums of the files the tables were produced from:

```
23c793d40839ad18fceef63445653feb8c2df3c30c690a0e3e139c0ef3f8b8f6  context.txt
ce8c9ba593cb0c125aa686648dc24ad02aa934b5bd25954fa1818ec3f87c9f9a  kube-bench-kg-control-1.log
1566e25e44e99abc086d60c0dc9adf9cb406b941d0145e14b1cd365c49eba3e6  kube-bench-kg-worker-1.log
99e444627e2d578874a25811e2a191a28fc8fc795e050eea622edd684341d901  kube-bench-kg-worker-2.log
6fa3256969381492d75386c9fb064d0bd45796b81658083f2dcb9464c293ca42  kubescape.json
beaa35d4e08f1ea0ebf5048629c1bd1aa3ac8e75a73fc7f56aa13820a45cb659  kubescape.log
```

To regenerate the tables: `make scan-summary DIR=~/.local/share/kubeguard/scans/baseline-20261015-235444`.

## Limits of this baseline

- **kube-bench has no profile for Kubernetes 1.36.** Version 0.16.0 (released 2026-08-05) maps Kubernetes up to 1.34 (`cis-1.12`) and cannot detect 1.36 by itself. The profile was therefore set by hand. The log of each Job carries the warning "Kubernetes version was not auto-detected ... Assuming default version 1.18" and the JSON has `detected_version: none`; every section of every node reports `version: cis-1.12`. Checks that CIS may have added or changed for newer Kubernetes versions are not covered.
- **WARN means "manual check", not "failed".** All 56 WARN results on the control-plane node and all 6 on each worker are of type Manual: kube-bench does not decide them. That includes all 34 checks of section 5 (policies).
- **kubescape cannot evaluate host-level controls from the CLI.** 50 of its 170 controls are "notEvaluated" because they need data that only the Kubescape operator collects (kubelet, control-plane and CNI information). These are the areas kube-bench covers. 5 more controls need manual review.
- **Same scores with the default settings.** A scan with kubescape's default downloaded exceptions (298 entries, which mark findings "w/exceptions") gave identical framework scores. The pinned, empty exceptions list was chosen so that every finding is reported and a re-scan cannot drift because a remote list changed.
- **Scores describe configuration, not security.** Neither scanner tests whether an attack works. The nodes also still had their internet interface attached (the isolation step was skipped at the end of Phase 1); no check covers that.

## Results


```
label: baseline
date: 2026-10-15T23:54:44+06:00
git: feat/p2-baseline-hardening @ 47f2ee2
kube-bench: v0.16.0, profile cis-1.12, targets: control node master,etcd,controlplane,policies,node; workers node
kubescape: Your current version is: v4.0.16, controls v2.0.38, frameworks nsa,mitre,cis-v1.12.0
kubernetes server: v1.36.5
nodes:
kg-control-1   Ready   control-plane   4h10m   v1.36.5   10.77.0.10   <none>   Ubuntu 24.04.5 LTS   6.8.0-146-generic (amd64)   containerd://2.3.6
kg-worker-1    Ready   <none>          4h9m    v1.36.5   10.77.0.11   <none>   Ubuntu 24.04.5 LTS   6.8.0-146-generic (amd64)   containerd://2.3.6
kg-worker-2    Ready   <none>          4h9m    v1.36.5   10.77.0.12   <none>   Ubuntu 24.04.5 LTS   6.8.0-147-generic (amd64)   containerd://2.3.6
```

### kube-bench

| Node | PASS | FAIL | WARN | INFO |
|---|---:|---:|---:|---:|
| kg-control-1 | 62 | 13 | 56 | 0 |
| kg-worker-1 | 16 | 3 | 6 | 0 |
| kg-worker-2 | 16 | 3 | 6 | 0 |

Sections on the control-plane node:

| Section | PASS | FAIL | WARN | INFO |
|---|---:|---:|---:|---:|
| 1 Control Plane Security Configuration | 39 | 10 | 11 | 0 |
| 2 Etcd Node Configuration | 7 | 0 | 0 | 0 |
| 3 Control Plane Configuration | 0 | 0 | 5 | 0 |
| 4 Worker Node Security Configuration | 16 | 3 | 6 | 0 |
| 5 Kubernetes Policies | 0 | 0 | 34 | 0 |

#### FAIL on kg-control-1 (13)

| Check | Type | Description |
|---|---|---|
| 1.1.12 | Automated | Ensure that the etcd data directory ownership is set to etcd:etcd |
| 1.2.5 | Automated | Ensure that the --kubelet-certificate-authority argument is set as appropriate |
| 1.2.15 | Automated | Ensure that the --profiling argument is set to false |
| 1.2.16 | Automated | Ensure that the --audit-log-path argument is set |
| 1.2.17 | Automated | Ensure that the --audit-log-maxage argument is set to 30 or as appropriate |
| 1.2.18 | Automated | Ensure that the --audit-log-maxbackup argument is set to 10 or as appropriate |
| 1.2.19 | Automated | Ensure that the --audit-log-maxsize argument is set to 100 or as appropriate |
| 1.2.30 | Automated | Ensure that the --service-account-extend-token-expiration parameter is set to false |
| 1.3.2 | Automated | Ensure that the --profiling argument is set to false |
| 1.4.1 | Automated | Ensure that the --profiling argument is set to false |
| 4.1.1 | Automated | Ensure that the kubelet service file permissions are set to 600 or more restrictive |
| 4.1.9 | Automated | If the kubelet config.yaml configuration file is being used validate permissions set to 600 or more restric... |
| 4.3.1 | Automated | Ensure that the kube-proxy metrics service is bound to localhost |

#### FAIL on kg-worker-1 (3)

| Check | Type | Description |
|---|---|---|
| 4.1.1 | Automated | Ensure that the kubelet service file permissions are set to 600 or more restrictive |
| 4.1.9 | Automated | If the kubelet config.yaml configuration file is being used validate permissions set to 600 or more restric... |
| 4.3.1 | Automated | Ensure that the kube-proxy metrics service is bound to localhost |

#### FAIL on kg-worker-2 (3)

| Check | Type | Description |
|---|---|---|
| 4.1.1 | Automated | Ensure that the kubelet service file permissions are set to 600 or more restrictive |
| 4.1.9 | Automated | If the kubelet config.yaml configuration file is being used validate permissions set to 600 or more restric... |
| 4.3.1 | Automated | Ensure that the kube-proxy metrics service is bound to localhost |

WARN on kg-control-1 (56; {'Manual': 56}): 1.1.9, 1.1.10, 1.2.1, 1.2.3, 1.2.9, 1.2.11, 1.2.20, 1.2.27, 1.2.28, 1.2.29, 1.3.1, 3.1.1, 3.1.2, 3.1.3, 3.2.1, 3.2.2, 4.1.3, 4.1.4, 4.2.9, 4.2.12, 4.2.13, 4.2.14, 5.1.1, 5.1.2, 5.1.3, 5.1.4, 5.1.5, 5.1.6, 5.1.7, 5.1.8, 5.1.9, 5.1.10, 5.1.11, 5.1.12, 5.1.13, 5.2.1, 5.2.2, 5.2.3, 5.2.4, 5.2.5, 5.2.6, 5.2.7, 5.2.8, 5.2.9, 5.2.10, 5.2.11, 5.2.12, 5.3.1, 5.3.2, 5.4.1, 5.4.2, 5.5.1, 5.6.1, 5.6.2, 5.6.3, 5.6.4

WARN on kg-worker-1 (6; {'Manual': 6}): 4.1.3, 4.1.4, 4.2.9, 4.2.12, 4.2.13, 4.2.14

WARN on kg-worker-2 (6; {'Manual': 6}): 4.1.3, 4.1.4, 4.2.9, 4.2.12, 4.2.13, 4.2.14

### kubescape

| Framework | Compliance score | Controls passed | failed | skipped | Resources passed | failed |
|---|---:|---:|---:|---:|---:|---:|
| NSA | 53.18 | 4 | 20 | 2 | 192 | 31 |
| MITRE | 60.39 | 7 | 17 | 2 | 82 | 86 |
| cis-v1.12.0 | 36.20 | 33 | 45 | 53 | 266 | 63 |

Overall compliance score 41.52. Controls over all frameworks (170): 42 passed, 73 failed, 55 skipped (50 notEvaluated, 5 manual review). Failed controls by severity: {'criticalSeverity': 0, 'highSeverity': 19, 'mediumSeverity': 48, 'lowSeverity': 6}.

#### Failed controls of High or Critical severity (19)

| Control | Name | Severity | Resources failed | passed |
|---|---|---|---:|---:|
| C-0012 | Applications credentials in configuration files | High | 2 | 66 |
| C-0015 | List Kubernetes secrets | High | 14 | 74 |
| C-0038 | Host PID/IPC privileges | High | 1 | 17 |
| C-0041 | CIS-5.2.5 Minimize the admission of containers wishing to share the host netw... | High | 8 | 10 |
| C-0045 | Writable hostPath mount | High | 3 | 15 |
| C-0046 | Insecure capabilities | High | 2 | 16 |
| C-0048 | HostPath mount | High | 7 | 11 |
| C-0057 | Privileged container | High | 2 | 16 |
| C-0113 | CIS-1.2.1 Ensure that the --anonymous-auth argument is set to false | High | 1 | 0 |
| C-0117 | CIS-1.2.5 Ensure that the --kubelet-certificate-authority argument is set as ... | High | 1 | 0 |
| C-0130 | CIS-1.2.16 Ensure that the --audit-log-path argument is set | High | 1 | 0 |
| C-0141 | CIS-1.2.27 Ensure that the --encryption-provider-config argument is set as ap... | High | 1 | 0 |
| C-0185 | CIS-5.1.1 Ensure that the cluster-admin role is only used where required | High | 2 | 63 |
| C-0187 | CIS-5.1.3 Minimize wildcard use in Roles and ClusterRoles | High | 2 | 86 |
| C-0193 | CIS-5.2.2 Minimize the admission of privileged containers | High | 9 | 0 |
| C-0202 | CIS-5.2.10 Minimize the admission of Windows HostProcess Containers | High | 9 | 0 |
| C-0211 | CIS-5.6.3 Apply Security Context to Your Pods and Containers | High | 18 | 0 |
| C-0270 | Ensure CPU limits are set | High | 18 | 0 |
| C-0271 | Ensure memory limits are set | High | 12 | 6 |


## Reproducibility of the baseline

Two earlier trial scans of the same unchanged cluster (made while the tooling was being written) were compared with this baseline using `make scan-compare`:

- kube-bench, trial against baseline: every total is equal on all three nodes, and no check changed status.
- kubescape, trial against baseline: every framework score is equal, and no control changed status or number of failed resources.

## What the scan changed

- Namespace `scanners` was added (label `pod-security.kubernetes.io/enforce=privileged`, the documented exemption for kube-bench, to be reviewed in P2-U4). It is empty after a scan: the Jobs and pods are deleted by the script.
- The image `aquasec/kube-bench:v0.16.0` was pulled onto the three nodes (internet window).
- Nothing was created on the node file systems: only host paths that exist on the nodes are mounted, read-only.

## Acceptance

| Check | Result |
|---|---|
| Baseline scores of both scanners exist, taken before any change to the cluster | Pass (this report; raw files outside git with checksums above) |
| Scanner versions and inputs recorded | Pass (tables above and `infra/versions.env`) |
| Scores saved under `docs/reports/` | Pass |

## Notes

- Which findings to fix and which to accept is decided in P2-U2 (`docs/reports/P2-U2-cis-fixes.md`).
- The downloaded kubescape binary was verified against the SHA256 in the release's `checksums.sha256`. Cosign is not installed, so this proves integrity only, not that the release was signed by the project.
