# P2-U2 evidence: CIS findings fixed, and findings accepted with a reason

Date: 2026-10-16. Branch: `feat/p2-baseline-hardening`. Cluster: Kubernetes 1.36.5, three nodes (`kg-control-1`, `kg-worker-1`, `kg-worker-2`). The hardening was applied with `make ansible-apply` by the assistant at the researcher's instruction ("do it by yourself"). The assistant did not produce any number in this report: scores and counts are copied by script from the scanners' own output (`infra/scans/summarize.py`) and from the test runs; the paragraphs around them are the assistant's reading.

Baseline: [P2-U1-baseline.md](P2-U1-baseline.md) (scan `baseline-20261015-235444`, kube-bench v0.16.0 with profile `cis-1.12`, kubescape v4.0.16 with controls `v2.0.38`). Runbook: [hardening.md](../runbooks/hardening.md). The encryption and audit parts of the same change (P2-U6) are in [P2-U6-encryption-audit-evidence.md](P2-U6-encryption-audit-evidence.md).

## What was applied, in order

| Step | Command | Restore point | Result |
|---|---|---|---|
| 1 | `make vms-snapshot SNAP=pre-u2`, `make etcd-snapshot` | VM snapshots `pre-u2`, etcd snapshot `etcd-20261016-004023.db` | done |
| 2 | `make ansible-apply ANSIBLE_ARGS="-e hardening_audit_enabled=false -e hardening_encryption_enabled=false"` (U2 only) | | `failed=0` on all three nodes; a first attempt stopped early, see "Side effects" |
| 3 | `make test-hardening` | | every U2 control passed; the two U6 controls failed, as expected before U6 |
| 4 | `make net-test-u6`, `net-test-u7`, `net-test-u8` | | all three passed |
| 5 | `make vms-snapshot SNAP=pre-u6`, `make etcd-snapshot` | VM snapshots `pre-u6`, etcd snapshot `etcd-20261016-010224.db` | done; the hardened nodes also came back healthy after the VM restart |
| 6 | `make ansible-apply` (U6, both switches on) | | `failed=0` on all three nodes |
| 7 | `make ansible-test` | | the second playbook run changed nothing on any node |
| 8 | `make drill-etcd` | | snapshot, restore and verify passed with encrypted Secrets |
| 9 | `make net-test-u6`, `net-test-u7`, `net-test-u8` again | | all three passed |
| 10 | `make test-hardening`, then `make scan LABEL=after-hardening` | | all test lines passed; scan below |

## How the decisions were made

The unit plan leaves the choice of which findings to fix and which to accept to the researcher. The triage below was proposed by the assistant on 2026-10-16, after the researcher asked for the branch to be completed, and is open to change; a change is recorded here with its date.

Rules used:

1. Fix every automated FAIL that the lab can carry.
2. Fix manual checks (kube-bench WARN) that are cheap and can be tested.
3. Accept a finding, with a reason, when the check does not apply to this cluster, when fixing it would break the isolated lab, or when a later unit owns it.
4. The scanner configuration does not change between the baseline and the re-scan. No exception is added to improve a score.

A note on reading the scans: kube-bench lists many checks as `Manual`. With this profile it still runs the audit command of a manual check: it reports PASS when the command finds the setting and WARN when it does not (examples below: 1.2.3, 4.2.13). A few checks cannot be decided by a command (for example 3.2.2, whether the audit policy covers the key security concerns); they stay WARN and need a person to read the policy.

## kube-bench FAIL at the baseline

| Check | Node | Decision | What changed, or why it is accepted | Result in the re-scan |
|---|---|---|---|---|
| 1.1.12 etcd data directory owned by etcd:etcd | control | Fix | The role creates the `etcd` system user and sets `/var/lib/etcd` to `etcd:etcd`, mode 700. The etcd container runs as root and is not affected | FAIL -> PASS |
| 1.2.5 `--kubelet-certificate-authority` | control | Fix | Kubelet `serverTLSBootstrap`, each node's own certificate request approved, the flag set | FAIL -> PASS |
| 1.2.15, 1.3.2, 1.4.1 `--profiling=false` | control | Fix | The flag on the API server, controller manager and scheduler | FAIL -> PASS (all three) |
| 1.2.16 to 1.2.19 audit log path, maxage, maxbackup, maxsize | control | Fix (P2-U6) | Audit policy and the four flags | FAIL -> PASS (all four) |
| 1.2.30 `--service-account-extend-token-expiration=false` | control | Fix | The flag. Side effect: a pod that reads its token once and never again stops working when the token expires; client libraries re-read it | FAIL -> PASS |
| 4.1.1 kubelet service file mode, 4.1.9 kubelet `config.yaml` mode | control, both workers | Fix | Mode 600 on both files, on every node | FAIL -> PASS on all three nodes |
| 4.3.1 kube-proxy metrics bound to localhost | control, both workers | **Accept: not applicable** | There is no kube-proxy: Cilium replaces it (P1-U5). The check runs `ps -fC proxy`, finds no process, and kube-bench records "failed to run ... exit status 1" (raw record in the baseline scan) | stays FAIL on all three nodes, as expected |

## kube-bench WARN (manual checks) at the baseline

| Check | Decision | Reason or change | Result in the re-scan |
|---|---|---|---|
| 1.2.1 anonymous auth | Fix, differently | `--anonymous-auth=false` would make the API server's own probes fail, because kubeadm's probes are anonymous. Anonymous requests are limited to `/livez`, `/readyz` and `/healthz` with an `AuthenticationConfiguration`. Test `anonymous` passes | **stays WARN**: the audit looks for the flag only. kubescape C-0113 stays failed for the same reason |
| 1.2.3 DenyServiceExternalIPs | Fix | Admission plugin added | WARN -> PASS |
| 1.2.27, 1.2.28 encryption provider | Fix (P2-U6) | `EncryptionConfiguration` with secretbox | WARN -> PASS (both) |
| 1.2.29 API server strong ciphers | Fix | `--tls-min-version`, `--tls-cipher-suites` (ECDHE with AES-GCM or ChaCha20) | WARN -> PASS |
| 3.2.1 minimal audit policy | Fix (P2-U6) | Policy file `roles/hardening/files/audit-policy.yaml` | WARN -> PASS |
| 3.2.2 audit policy covers key security concerns | Fix (P2-U6), review left to the researcher | The policy keeps the body of changes to workloads, RBAC, policies, webhooks and certificates, and logs Secret access at metadata level | stays WARN: no command can decide it |
| 4.2.9 kubelet `--tls-cert-file` and key | Accept | The serving certificate comes from `serverTLSBootstrap` (signed by the cluster CA, renewed by the kubelet). No fixed `tlsCertFile` is set, because the kubelet manages the pair itself | stays WARN on all three nodes |
| 4.2.12 kubelet strong ciphers | Fix | `tlsMinVersion`, `tlsCipherSuites` in the kubelet configuration | WARN -> PASS on all three nodes |
| 4.2.13 PID limit | Fix | `podPidsLimit: 4096` | WARN -> PASS on all three nodes |
| 4.2.14 `--seccomp-default` | Fix | `seccompDefault: true` | WARN -> PASS on all three nodes |
| 1.1.9, 1.1.10 CNI file mode and owner | Already met | `/etc/cni/net.d/05-cilium.conflist` is `600 root:root` on `kg-control-1` (checked by hand on 2026-10-16) | stays WARN (the audit command cannot decide it) |
| 1.2.9 EventRateLimit | Accept | An alpha plugin that needs its own configuration. Low value on a single-tenant lab API | stays WARN |
| 1.2.11 AlwaysPullImages | Accept | It forces a registry pull on every pod start, and the nodes are isolated after the build window and run from cached images. What it protects against is handled later by a registry allowlist (P2-U7) and image scanning (P2-U9) | stays WARN |
| 1.2.20 `--request-timeout` | Accept | The default of 60 s is appropriate for a three-node lab | stays WARN |
| 1.3.1 `--terminated-pod-gc-threshold` | Accept | The default is appropriate for a three-node lab | stays WARN |
| 3.1.1, 3.1.2, 3.1.3 authentication methods for users | Accept for now | The isolated lab has no identity provider. The admin kubeconfig uses a client certificate. Decided again in P2-U3 (RBAC audit) | stay WARN |
| 4.1.3, 4.1.4 proxy kubeconfig | Not applicable | No kube-proxy | stay WARN |
| 5.1.1 to 5.1.13 RBAC | Later: P2-U3 | RBAC audit to least privilege | unchanged |
| 5.2.1 to 5.2.12, 5.6.2 to 5.6.4 pod admission, security context, seccomp in pods, default namespace | Later: P2-U4, P2-U7 | Pod Security Admission and Kyverno | unchanged |
| 5.3.1, 5.3.2 network policies | Later: P2-U5 | Default-deny per namespace (5.3.1 is already true: Cilium supports NetworkPolicy) | unchanged |
| 5.4.1, 5.4.2, 5.5.1 Secrets as files, external secret storage, image provenance | Later: P2-U9 | Secrets workflow and image scanning | unchanged |
| 5.6.1 namespaces as administrative boundaries | Later: P2-U3, P2-U4 | Part of the RBAC and admission work | unchanged |

## kubescape: failed controls of High severity at the baseline

| Control | Subject | Owner | Result in the re-scan |
|---|---|---|---|
| C-0113 | Anonymous authentication | P2-U2 (done differently, see 1.2.1) | **still failed** |
| C-0117 | Kubelet certificate authority | P2-U2 | failed -> passed |
| C-0130 | Audit log path | P2-U6 | failed -> passed |
| C-0141 | Encryption provider config | P2-U6 | failed -> passed |
| C-0185, C-0187, C-0015 | Use of cluster-admin, wildcard roles, who can list Secrets | P2-U3 | unchanged |
| C-0038, C-0041, C-0045, C-0046, C-0048, C-0057, C-0193, C-0202, C-0211 | Host PID, IPC and network, hostPath, capabilities, privileged containers, security context | P2-U4 and P2-U7. Exemptions for the system namespaces are part of decision H4 | unchanged, except C-0045 (see "Side effects") |
| C-0270, C-0271 | CPU and memory limits | P2-U7 (Kyverno) | unchanged |
| C-0012 | Credentials in configuration files | P2-U9 (needs a look at the two resources first) | unchanged |

Controls of lower severity that also changed from failed to passed are listed in the comparison below (C-0066 and C-0067 for Secret encryption and audit logs, C-0129, C-0131, C-0145, C-0151, C-0160, C-0277, C-0283 and C-0290).

## Results

### Negative tests (`make test-hardening`, run after both applies)

Before the apply, every control failed on the unhardened cluster; the only passing lines were the "must still work" checks (anonymous `/readyz`, the API server reaching the kubelet, the decrypted read-back of a Secret).

```
== anonymous access (CIS 1.2.1)
PASS  anonymous GET /version is refused (401)
PASS  anonymous GET /api/v1/namespaces is refused (401)
PASS  anonymous GET /readyz is still accepted (200): the API server probes work
== Services with external IPs (CIS 1.2.3)
PASS  a Service with externalIPs is rejected at admission
== profiling endpoints (CIS 1.2.15, 1.3.2, 1.4.1)
PASS  the API server does not serve /debug/pprof/
PASS  kube-controller-manager runs with --profiling=false
PASS  kube-scheduler runs with --profiling=false
== file permissions and ownership (CIS 4.1.1, 4.1.9, 1.1.12)
PASS  kg-control-1: kubelet.service and config.yaml are 600 root:root
PASS  kg-control-1: /var/lib/etcd is 700 etcd:etcd
PASS  kg-worker-1: kubelet.service and config.yaml are 600 root:root
PASS  kg-worker-2: kubelet.service and config.yaml are 600 root:root
== kubelet serving certificates (CIS 1.2.5)
PASS  kube-apiserver verifies kubelet certificates (--kubelet-certificate-authority is set)
PASS  kg-control-1: the kubelet serves a certificate signed by the cluster CA for 10.77.0.10
PASS  kg-control-1: the API server reaches the kubelet
PASS  kg-worker-1: the kubelet serves a certificate signed by the cluster CA for 10.77.0.11
PASS  kg-worker-1: the API server reaches the kubelet
PASS  kg-worker-2: the kubelet serves a certificate signed by the cluster CA for 10.77.0.12
PASS  kg-worker-2: the API server reaches the kubelet
== strong TLS ciphers (CIS 1.2.29, 4.2.12)
PASS  kube-apiserver: a TLS 1.2 handshake with ECDHE-RSA-AES128-GCM-SHA256 works
PASS  kube-apiserver: the weak suite AES128-SHA (CBC, SHA-1) is refused
PASS  kubelet-kg-control-1: a TLS 1.2 handshake with ECDHE-ECDSA-AES128-GCM-SHA256 works
PASS  kubelet-kg-control-1: the weak suite AES128-SHA (CBC, SHA-1) is refused
PASS  kubelet-kg-worker-1: a TLS 1.2 handshake with ECDHE-ECDSA-AES128-GCM-SHA256 works
PASS  kubelet-kg-worker-1: the weak suite AES128-SHA (CBC, SHA-1) is refused
PASS  kubelet-kg-worker-2: a TLS 1.2 handshake with ECDHE-ECDSA-AES128-GCM-SHA256 works
PASS  kubelet-kg-worker-2: the weak suite AES128-SHA (CBC, SHA-1) is refused
== PID limit per pod (CIS 4.2.13)
PASS  kg-worker-1: the pod cgroup allows at most 4096 processes
PASS  kg-worker-2: the pod cgroup allows at most 4096 processes
== default seccomp profile (CIS 4.2.14)
PASS  kg-worker-1: a pod without a seccomp profile runs with the runtime default filter (Seccomp: 2)
PASS  kg-worker-2: a pod without a seccomp profile runs with the runtime default filter (Seccomp: 2)
== Secrets encrypted at rest (CIS 1.2.27, 1.2.28)
PASS  the plaintext value is not found anywhere in the etcd record
PASS  the etcd record carries the prefix k8s:enc:secretbox:v1:key1
PASS  the API server still returns the decrypted value
PASS  every Secret in etcd is stored encrypted
== API audit log (CIS 1.2.16 to 1.2.19, 3.2.1, 3.2.2)
PASS  the audit log exists and is 600 root
PASS  creating a namespace is logged at level Request
PASS  reading a Secret is logged at level Metadata (who and when, no content)
PASS  no Secret value appears in the audit log
INFO  audit log size: 3.7M

ALL PASSED
```

### Re-scan compared with the baseline

Scan `after-hardening-20261016-011514`, same scanners and inputs as the baseline. Output of `make scan-compare BEFORE=baseline-20261015-235444 AFTER=after-hardening-20261016-011514`, pasted by script (headings moved one level down, nothing else changed).

Before: `baseline-20261015-235444`  
After: `after-hardening-20261016-011514`

### kube-bench totals

| Node | PASS | FAIL | WARN | INFO |
|---|---:|---:|---:|---:|
| kg-control-1 | 62 -> 82 | 13 -> 1 | 56 -> 48 | 0 -> 0 |
| kg-worker-1 | 16 -> 21 | 3 -> 1 | 6 -> 3 | 0 -> 0 |
| kg-worker-2 | 16 -> 21 | 3 -> 1 | 6 -> 3 | 0 -> 0 |

### kube-bench checks whose status changed

| Node | Check | Before | After | Description |
|---|---|---|---|---|
| kg-control-1 | 1.1.12 | FAIL | PASS | Ensure that the etcd data directory ownership is set to etcd:etcd |
| kg-control-1 | 1.2.3 | WARN | PASS | Ensure that the --DenyServiceExternalIPs is set |
| kg-control-1 | 1.2.5 | FAIL | PASS | Ensure that the --kubelet-certificate-authority argument is set as appropriate |
| kg-control-1 | 1.2.15 | FAIL | PASS | Ensure that the --profiling argument is set to false |
| kg-control-1 | 1.2.16 | FAIL | PASS | Ensure that the --audit-log-path argument is set |
| kg-control-1 | 1.2.17 | FAIL | PASS | Ensure that the --audit-log-maxage argument is set to 30 or as appropriate |
| kg-control-1 | 1.2.18 | FAIL | PASS | Ensure that the --audit-log-maxbackup argument is set to 10 or as appropriate |
| kg-control-1 | 1.2.19 | FAIL | PASS | Ensure that the --audit-log-maxsize argument is set to 100 or as appropriate |
| kg-control-1 | 1.2.27 | WARN | PASS | Ensure that the --encryption-provider-config argument is set as appropriate |
| kg-control-1 | 1.2.28 | WARN | PASS | Ensure that encryption providers are appropriately configured |
| kg-control-1 | 1.2.29 | WARN | PASS | Ensure that the API Server only makes use of Strong Cryptographic Ciphers |
| kg-control-1 | 1.2.30 | FAIL | PASS | Ensure that the --service-account-extend-token-expiration parameter is set to false |
| kg-control-1 | 1.3.2 | FAIL | PASS | Ensure that the --profiling argument is set to false |
| kg-control-1 | 1.4.1 | FAIL | PASS | Ensure that the --profiling argument is set to false |
| kg-control-1 | 3.2.1 | WARN | PASS | Ensure that a minimal audit policy is created |
| kg-control-1 | 4.1.1 | FAIL | PASS | Ensure that the kubelet service file permissions are set to 600 or more restrictive |
| kg-control-1 | 4.1.9 | FAIL | PASS | If the kubelet config.yaml configuration file is being used validate permissions set to... |
| kg-control-1 | 4.2.12 | WARN | PASS | Ensure that the Kubelet only makes use of Strong Cryptographic Ciphers |
| kg-control-1 | 4.2.13 | WARN | PASS | Ensure that a limit is set on pod PIDs |
| kg-control-1 | 4.2.14 | WARN | PASS | Ensure that the --seccomp-default parameter is set to true |
| kg-worker-1 | 4.1.1 | FAIL | PASS | Ensure that the kubelet service file permissions are set to 600 or more restrictive |
| kg-worker-1 | 4.1.9 | FAIL | PASS | If the kubelet config.yaml configuration file is being used validate permissions set to... |
| kg-worker-1 | 4.2.12 | WARN | PASS | Ensure that the Kubelet only makes use of Strong Cryptographic Ciphers |
| kg-worker-1 | 4.2.13 | WARN | PASS | Ensure that a limit is set on pod PIDs |
| kg-worker-1 | 4.2.14 | WARN | PASS | Ensure that the --seccomp-default parameter is set to true |
| kg-worker-2 | 4.1.1 | FAIL | PASS | Ensure that the kubelet service file permissions are set to 600 or more restrictive |
| kg-worker-2 | 4.1.9 | FAIL | PASS | If the kubelet config.yaml configuration file is being used validate permissions set to... |
| kg-worker-2 | 4.2.12 | WARN | PASS | Ensure that the Kubelet only makes use of Strong Cryptographic Ciphers |
| kg-worker-2 | 4.2.13 | WARN | PASS | Ensure that a limit is set on pod PIDs |
| kg-worker-2 | 4.2.14 | WARN | PASS | Ensure that the --seccomp-default parameter is set to true |

### kubescape compliance score per framework

| Framework | Before | After |
|---|---:|---:|
| NSA | 53.18 | 60.87 |
| MITRE | 60.39 | 67.87 |
| cis-v1.12.0 | 36.20 | 44.60 |
| overall | 41.52 | 49.13 |

### kubescape controls that changed (status or failed resources)

| Control | Name | Status before -> after | Failed resources before -> after |
|---|---|---|---|
| C-0045 | Writable hostPath mount | failed -> failed | 3 -> 4 |
| C-0066 | Secret/etcd encryption enabled | failed -> passed | 1 -> 0 |
| C-0067 | Audit logs enabled | failed -> passed | 1 -> 0 |
| C-0117 | CIS-1.2.5 Ensure that the --kubelet-certificate-authority argument ... | failed -> passed | 1 -> 0 |
| C-0129 | CIS-1.2.15 Ensure that the --profiling argument is set to false | failed -> passed | 1 -> 0 |
| C-0130 | CIS-1.2.16 Ensure that the --audit-log-path argument is set | failed -> passed | 1 -> 0 |
| C-0131 | CIS-1.2.17 Ensure that the --audit-log-maxage argument is set to 30... | failed -> passed | 1 -> 0 |
| C-0141 | CIS-1.2.27 Ensure that the --encryption-provider-config argument is... | failed -> passed | 1 -> 0 |
| C-0145 | CIS-1.3.2 Ensure that the --profiling argument is set to false | failed -> passed | 1 -> 0 |
| C-0151 | CIS-1.4.1 Ensure that the --profiling argument is set to false | failed -> passed | 1 -> 0 |
| C-0160 | CIS-3.2.1 Ensure that a minimal audit policy is created | failed -> passed | 1 -> 0 |
| C-0277 | CIS-1.2.29 Ensure that the API Server only makes use of Strong Cryp... | failed -> passed | 1 -> 0 |
| C-0283 | CIS-1.2.3 Ensure that the DenyServiceExternalIPs is set | failed -> passed | 1 -> 0 |
| C-0290 | CIS-1.2.30 Ensure that the --service-account-extend-token-expiratio... | failed -> passed | 1 -> 0 |

## Findings that remain, and why

- kube-bench **4.3.1** (three nodes): no kube-proxy exists. Accepted, not applicable.
- kube-bench **1.2.1** and kubescape **C-0113**: both look for `--anonymous-auth=false`, which cannot be set (above). The control works in effect and is tested (`anonymous`); the scanners keep flagging it. If the scores are quoted in the paper, quote this deviation with them.
- Every WARN marked Accept or Later in the tables above.
- All kubescape controls not listed as changed in the comparison.

## Side effects found while applying

1. **Switch values were strings.** The first U2 apply stopped in the preparation play: `-e hardening_audit_enabled=false` reaches Ansible as the string "false", which this ansible-core refuses in a `when:` and which counts as true in a plain Jinja `if`. Nothing on the API server, the kubelets or the other nodes had changed (the run had only created empty directories and the authentication file on the control node). The role now converts both switches with `| bool` (commit `7a0f384`); the second apply passed.
2. **A stray test namespace.** An earlier audit-test run left the namespace `audit-probe-16722136` behind, because the test's cleanup was skipped when a step before it failed. The first after-scan (`after-u2-u6-20261016-011143`) therefore showed one extra namespace in several kubescape counts. That scan is **superseded**: the namespace was deleted, the test now always removes its probe namespace, and the scan above was taken on the clean cluster. The raw files of the first scan stay in `~/.local/share/kubeguard/scans/` for the record.
3. **C-0045 (writable hostPath) rose from 3 to 4 failing resources.** The new one is `Pod/kube-system/kube-apiserver-kg-control-1`, which now mounts the audit log directory read-write so that it can write the log. The same control already flags the etcd pod for its data directory, Cilium and cilium-envoy. This is the cost of audit logging and is accepted.
4. **Certificate requests.** Each node's kubelet-serving request needed a few seconds to appear after the kubelet restart; the role retries until the certificate is issued and verifies it before the API server flag is set. The rejoin drill and a new worker need the same approval ([hardening.md](../runbooks/hardening.md)).
5. The P1 acceptance checks (`net-test-u6`, `net-test-u7`, `net-test-u8`) passed after U2 and again after U6; all pods were Running and all nodes Ready after each step.

## Reproducibility

- The change is the Ansible role `hardening` plus the kubeadm configuration template. `make ansible-test` runs the playbook twice; the second run changed nothing (step 7).
- `make rebuild CONFIRM=yes` builds the cluster hardened from the start and ends with `make test-hardening`. **That path has not been run yet**; it is part of gate G1 (decision H10). The in-place path above is what this report proves.
- Raw scan output is outside git in `~/.local/share/kubeguard/scans/after-hardening-20261016-011514/` (directory mode 700). Checksums of the files the comparison was produced from:

```
8102051bb0205df09a2965415aa1255a5406747c45f12d6954957329cd521105  context.txt
549013d56c25d70c48a5bb7179447e2c842ce2bb0e870f44a760ded8e95a03ce  kube-bench-kg-control-1.log
2314315ccfd24194c00250e93c7ffce65f705f3635ce764964290025584d245d  kube-bench-kg-worker-1.log
cfc92794926e9248a6b68046dda25daded5098cdec325bb42810038a95cef236  kube-bench-kg-worker-2.log
dc54115b66be4fe985c4b536f651cd604b25f6a2e7d67fe10f1b2716be226523  kubescape.json
896c772542ed60573c0fb786f039c4eabbda2f206749e19e097b6ea509272d57  kubescape.log
```

- The scan context file records git commit `7a0f384` plus uncommitted changes in the working tree at that time (the test cleanup fix and the evidence script; neither is used by the scanners).
- To regenerate the tables: `make scan-compare BEFORE=baseline-20261015-235444 AFTER=after-hardening-20261016-011514`.

## Acceptance

| Check (P2-U2: "Re-scan shows each fix") | Result |
|---|---|
| Every finding marked Fix shows the change in the re-scan, or in the negative test where the scanner cannot see it | Pass, with one exception: 1.2.1 and C-0113 (flag-only check; the control is tested) |
| Every remaining FAIL has an Accept row with a reason | Pass (4.3.1 only) |
| Idempotence: the second playbook run changes nothing | Pass |
| P1 acceptance checks still pass | Pass |
