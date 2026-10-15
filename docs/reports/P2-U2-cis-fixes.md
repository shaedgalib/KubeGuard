# P2-U2 evidence: CIS findings fixed, and findings accepted with a reason

Status: **draft, written before the hardening was applied.** The decisions below are final for review; the sections "Results" and "Side effects" are filled from the scanners and the test runs after the apply. No score in this report is typed by hand: scores are copied from the output of `infra/scans/summarize.py` (`make scan-summary`, `make scan-compare`).

Baseline: [P2-U1-baseline.md](P2-U1-baseline.md) (scan `baseline-20261015-235444`, kube-bench v0.16.0 with profile `cis-1.12`, kubescape v4.0.16 with controls `v2.0.38`). Runbook: [hardening.md](../runbooks/hardening.md).

## How the decisions were made

The unit plan leaves the choice of which findings to fix and which to accept to the researcher. The triage below was proposed by the assistant on 2026-10-16, after the researcher asked for the branch to be completed, and is open to change; a change is recorded here with its date.

Rules used:

1. Fix every automated FAIL that the lab can carry.
2. Fix manual checks (kube-bench WARN) that are cheap and can be tested.
3. Accept a finding, with a reason, when the check does not apply to this cluster, when fixing it would break the isolated lab, or when a later unit owns it.
4. The scanner configuration does not change between the baseline and the re-scan. No exception is added to improve a score.

A note on reading the re-scan: kube-bench cannot score checks that the benchmark marks `Manual`; they stay `WARN` whatever the cluster does. For those checks the evidence is the negative test in `infra/hardening/test.sh` (run first on the unhardened cluster, where it failed), and for some of them a kubescape control.

## kube-bench FAIL at the baseline

| Check | Node | Decision | What changes, or why it is accepted | Evidence |
|---|---|---|---|---|
| 1.1.12 etcd data directory owned by etcd:etcd | control | Fix | The role creates the `etcd` system user and sets `/var/lib/etcd` to `etcd:etcd`, mode 700. The etcd container runs as root and is not affected | test `files`, re-scan |
| 1.2.5 `--kubelet-certificate-authority` | control | Fix | Kubelet `serverTLSBootstrap`, the node's own certificate request approved, the flag set once every node serves a certificate from the cluster CA | test `kubelet-tls`, re-scan |
| 1.2.15, 1.3.2, 1.4.1 `--profiling=false` | control | Fix | The flag on the API server, controller manager and scheduler | test `profiling`, re-scan |
| 1.2.16 to 1.2.19 audit log path, maxage, maxbackup, maxsize | control | Fix in P2-U6 | Audit policy and the four flags | test `audit`, re-scan after U6 |
| 1.2.30 `--service-account-extend-token-expiration=false` | control | Fix | The flag. Side effect: a pod that reads its token once and never again stops working when the token expires; client libraries re-read it | re-scan, P1 checks |
| 4.1.1 kubelet service file mode, 4.1.9 kubelet `config.yaml` mode | control, both workers | Fix | Mode 600 on both files, on every node | test `files`, re-scan |
| 4.3.1 kube-proxy metrics bound to localhost | control, both workers | **Accept: not applicable** | There is no kube-proxy: Cilium replaces it (P1-U5). The check runs `ps -fC proxy`, finds no process, and kube-bench records "failed to run ... exit status 1" (raw record in the baseline scan). It stays FAIL after the fixes | raw record |

## kube-bench WARN (manual checks) at the baseline

| Check | Decision | Reason or change | Evidence |
|---|---|---|---|
| 1.2.1 anonymous auth | Fix, differently | `--anonymous-auth=false` would make the API server's own probes fail, because kubeadm's probes are anonymous. Anonymous requests are limited to `/livez`, `/readyz` and `/healthz` with an `AuthenticationConfiguration` | test `anonymous`; kubescape C-0113 |
| 1.2.3 DenyServiceExternalIPs | Fix | Admission plugin added | test `external-ips` |
| 1.2.27, 1.2.28 encryption provider | Fix in P2-U6 | `EncryptionConfiguration` with secretbox | test `etcd-encryption`; kubescape C-0141 |
| 1.2.29 API server strong ciphers | Fix | `--tls-min-version`, `--tls-cipher-suites` (ECDHE with AES-GCM or ChaCha20) | test `tls` |
| 3.2.1, 3.2.2 audit policy | Fix in P2-U6 | Policy file `roles/hardening/files/audit-policy.yaml` | test `audit` |
| 4.2.9 kubelet `--tls-cert-file` and key | Accept | The serving certificate comes from `serverTLSBootstrap` (signed by the cluster CA, renewed by the kubelet). No fixed `tlsCertFile` is set, because the kubelet manages the pair itself | test `kubelet-tls` |
| 4.2.12 kubelet strong ciphers | Fix | `tlsMinVersion`, `tlsCipherSuites` in the kubelet configuration | test `tls` |
| 4.2.13 PID limit | Fix | `podPidsLimit: 4096` | test `pid-limit` |
| 4.2.14 `--seccomp-default` | Fix | `seccompDefault: true` | test `seccomp` |
| 1.1.9, 1.1.10 CNI file mode and owner | Already met | `/etc/cni/net.d/05-cilium.conflist` is `600 root:root` on `kg-control-1` (checked by hand on 2026-10-16). Stays WARN because the benchmark marks it Manual | by hand |
| 1.2.9 EventRateLimit | Accept | An alpha plugin that needs its own configuration. Low value on a single-tenant lab API | none |
| 1.2.11 AlwaysPullImages | Accept | It forces a registry pull on every pod start, and the nodes are isolated after the build window and run from cached images. What it protects against is handled later by a registry allowlist (P2-U7) and image scanning (P2-U9) | none |
| 1.2.20 `--request-timeout` | Accept | The default of 60 s is appropriate for a three-node lab | none |
| 1.3.1 `--terminated-pod-gc-threshold` | Accept | The default is appropriate for a three-node lab | none |
| 3.1.1, 3.1.2, 3.1.3 authentication methods for users | Accept for now | The isolated lab has no identity provider. The admin kubeconfig uses a client certificate. Decided again in P2-U3 (RBAC audit) | none |
| 4.1.3, 4.1.4 proxy kubeconfig | Not applicable | No kube-proxy | none |
| 5.1.1 to 5.1.13 RBAC | Later: P2-U3 | RBAC audit to least privilege | |
| 5.2.1 to 5.2.12, 5.6.2 to 5.6.4 pod admission, security context, seccomp in pods, default namespace | Later: P2-U4, P2-U7 | Pod Security Admission and Kyverno | |
| 5.3.1, 5.3.2 network policies | Later: P2-U5 | Default-deny per namespace (5.3.1 is already true: Cilium supports NetworkPolicy) | |
| 5.4.1, 5.4.2, 5.5.1 Secrets as files, external secret storage, image provenance | Later: P2-U9 | Secrets workflow and image scanning | |
| 5.6.1 namespaces as administrative boundaries | Later: P2-U3, P2-U4 | Part of the RBAC and admission work | |

## kubescape: failed controls of High severity at the baseline

| Control | Subject | Owner |
|---|---|---|
| C-0113 | Anonymous authentication | P2-U2 |
| C-0117 | Kubelet certificate authority | P2-U2 |
| C-0130 | Audit log path | P2-U6 |
| C-0141 | Encryption provider config | P2-U6 |
| C-0185, C-0187, C-0015 | Use of cluster-admin, wildcard roles, who can list Secrets | P2-U3 |
| C-0038, C-0041, C-0045, C-0046, C-0048, C-0057, C-0193, C-0202, C-0211 | Host PID, IPC and network, hostPath, capabilities, privileged containers, security context | P2-U4 and P2-U7. Exemptions for the system namespaces are part of decision H4 |
| C-0270, C-0271 | CPU and memory limits | P2-U7 (Kyverno) |
| C-0012 | Credentials in configuration files | P2-U9 (needs a look at the two resources first) |

## Results

*To be filled after the apply.* Commands:

```bash
make scan LABEL=after-u2
make scan-compare BEFORE=baseline-20261015-235444 AFTER=<after dir>      # paste the output below, unchanged
make test-hardening                                                      # paste the PASS and FAIL lines below
```

### Negative tests

*(pending)*

### kube-bench: what changed

*(pending: totals per node and the checks whose status changed)*

### kubescape: what changed

*(pending: score per framework and the controls whose status changed)*

### Findings that remain, and why

*(pending: compared with the tables above; every remaining FAIL must have an "Accept" row)*

## Side effects found while applying

*(pending: anything that broke or changed behaviour, with the P1 checks `net-test-u6`, `net-test-u7` and `net-test-u8` run after the apply)*

## Reproducibility

The change is the Ansible role `hardening` plus the kubeadm configuration template. `make ansible-test` runs the playbook twice; the second run must change nothing. `make rebuild CONFIRM=yes` builds the cluster hardened from the start and ends with `make test-hardening`.

## Acceptance

*(pending)* P2-U2: "Re-scan shows each fix." P2-U6: "Secret unreadable in etcd, audit log present."
