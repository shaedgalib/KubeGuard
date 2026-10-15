# P2-U6 evidence: Secrets encrypted in etcd, API audit log with rotation

Date: 2026-10-16. Branch: `feat/p2-baseline-hardening`. Cluster: Kubernetes 1.36.5, one control-plane node with one etcd member. Applied with `make ansible-apply` by the assistant at the researcher's instruction ("do it by yourself"). The assistant did not produce any number in this report: every block below is the unchanged output of a script (`make hardening-evidence`, `make test-hardening`, `make drill-etcd`, `make ansible-test`); the paragraphs around the blocks are the assistant's reading. Runbook: [hardening.md](../runbooks/hardening.md). The CIS fixes applied in the same change are in [P2-U2-cis-fixes.md](P2-U2-cis-fixes.md).

Restore points taken before the change: VM snapshots `pre-u6` and etcd snapshot `etcd-20261016-010224.db`.

## What was changed

| Item | Setting |
|---|---|
| Encryption of Secrets (decision H8) | `EncryptionConfiguration` with the `secretbox` provider (key `key1`), then `identity` as a fallback so that data written before encryption can still be read. Resource: `secrets` |
| Key | 32 random bytes from `openssl rand -base64 32`, generated on the control node on the first run. Never printed or logged (`no_log`). On the node: `/etc/kubernetes/encryption/encryption-config.yaml`, mode 600, root. A copy is kept on the host, outside the repository, in `~/.local/share/kubeguard/encryption-keys/kg-control-1-<12 characters of the checksum>.yaml` (directory 700, file 600), one file per distinct key |
| Existing Secrets | Rewritten once (`kubectl get secrets -A -o json \| kubectl replace -f -`), guarded by a checksum file, so they are stored through secretbox |
| Audit policy (decision H9) | `roles/hardening/files/audit-policy.yaml`: the first matching rule wins. Secrets, ConfigMaps, service account tokens and token reviews at `Metadata` (never the content). Writes to pods, workloads, RBAC, network policies, webhooks, CRDs, certificates, Gateway and Kyverno objects at `Request` (body kept). Health URLs, leases, node status, component traffic, Cilium churn, endpoints and events not logged. Everything else at `Metadata` |
| Log and rotation | `/var/log/kubernetes/audit/audit.log`, `--audit-log-maxage=30`, `--audit-log-maxbackup=10`, `--audit-log-maxsize=100` |

The unit plan leaves the audit levels and the key handling to the researcher. Both were proposed by the assistant on 2026-10-16 after the researcher asked for the branch to be completed, and are open to change.

## Evidence from the control-plane node

Output of `make hardening-evidence` (read-only; etcd records are shown only as their first 26 bytes, audit events only as metadata fields):

```
== date: 2026-10-16T01:18:42+06:00

== API server flags for encryption, audit, authentication and TLS
--audit-log-maxage=30
--audit-log-maxbackup=10
--audit-log-maxsize=100
--audit-log-path=/var/log/kubernetes/audit/audit.log
--audit-policy-file=/etc/kubernetes/audit/audit-policy.yaml
--authentication-config=/etc/kubernetes/auth/authentication-config.yaml
--enable-admission-plugins=NodeRestriction,DenyServiceExternalIPs
--encryption-provider-config=/etc/kubernetes/encryption/encryption-config.yaml
--kubelet-certificate-authority=/etc/kubernetes/pki/ca.crt
--profiling=false
--service-account-extend-token-expiration=false
--tls-cert-file=/etc/kubernetes/pki/apiserver.crt
--tls-cipher-suites=TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384
--tls-min-version=VersionTLS12
--tls-private-key-file=/etc/kubernetes/pki/apiserver.key

== Encryption configuration on the node (mode, owner and name only)
700 root:root /etc/kubernetes/encryption
600 root:root /etc/kubernetes/encryption/encryption-config.yaml

== Key copy on the host (mode, owner and name only)
700 bs01699 /home/bs01699/.local/share/kubeguard/encryption-keys
600 bs01699 /home/bs01699/.local/share/kubeguard/encryption-keys/kg-control-1-f090bad89369.yaml

== Secrets in etcd, grouped by the first 26 bytes of the stored record (count, prefix)
     13 k8s:enc:secretbox:v1:key1:

== Audit log files (mode, owner, size, name)
600 root:root 5011137 /var/log/kubernetes/audit/audit.log
files in the directory: 1

== Disk of the control-plane node (df -h /var)
Filesystem      Size  Used Avail Use% Mounted on
/dev/vda1        19G  5.0G   14G  28% /

== Audit events: a Secret read (level Metadata, no request body) and a namespace creation (level Request, body kept)
{"level":"Metadata","verb":"get","user":"kubernetes-admin","resource":"secrets","namespace":"hardening-test","name":"enc-probe","code":404,"has_request_body":false}
{"level":"Metadata","verb":"get","user":"kubernetes-admin","resource":"secrets","namespace":"hardening-test","name":"audit-probe-767419596","code":200,"has_request_body":false}
{"level":"Request","verb":"create","user":"kubernetes-admin","resource":"namespaces","name":"hardening-test","code":201,"has_request_body":true}
{"level":"Request","verb":"create","user":"kubernetes-admin","resource":"namespaces","name":"audit-probe-767419596","code":201,"has_request_body":true}

== Audit events by level (count, level)
   3344 Metadata
    249 Request
```

Reading it:

- The API server runs with the audit and encryption flags (first block).
- Every Secret record in etcd starts with `k8s:enc:secretbox:v1:key1:`. A record that was still plaintext would start with `k8s` followed by protobuf bytes and would be listed as a second group.
- The key file is mode 600 on the node and on the host; both directories are mode 700.
- A Secret read is logged at `Metadata` and has no request body. A namespace creation is logged at `Request` and keeps its body.
- The audit log is a single file below the rotation limit; the root disk of the node has room for the full rotation budget (maxsize 100 MB for the current file and for each of up to 10 rotated files, about 1.1 GB at most).

## Negative tests

Part of the output of `make test-hardening` (the full run is in the U2 report). Written first and run on the unhardened cluster, where every line below failed except the read-back of the decrypted value, which passes before and after:

```
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
```

## Restore under encryption: the etcd drill

Output of `make drill-etcd`, filtered to the result lines (the etcdctl log lines are left out). The drill creates a ConfigMap and a Secret, takes a snapshot, deletes both and creates two others, restores the snapshot and checks the state. The snapshot is saved with a `.key-id` file naming the key, and the restore ends with a check that the API can read the Secrets again.

```
== 0. wait for the API
== 1. state before the snapshot
PASS  configmap drill-before created
PASS  secret drill-secret-before created
== 2. snapshot
copied to host: /home/bs01699/.local/share/kubeguard/etcd-backups/etcd-20261016-010939.db (31096864 bytes, sha256 d7df51ecf2c7beee...)
encryption key f090bad89369 recorded in /home/bs01699/.local/share/kubeguard/etcd-backups/etcd-20261016-010939.key-id
INFO  Secrets in this snapshot are encrypted with key f090bad89369
== 3. change the cluster after the snapshot
PASS  drill-before deleted, drill-after created
== 4. restore from the snapshot
uploading snapshot to kg-control-1
API ready
Secrets readable after the restore
== 5. verify
PASS  drill-before is back (state as of the snapshot)
PASS  drill-after is gone
PASS  drill-secret-before is back and its value decrypts correctly
PASS  drill-secret-after is gone
PASS  all nodes Ready
PASS  kube-system pods Running
snapshot kept at: /home/bs01699/.local/share/kubeguard/etcd-backups/etcd-20261016-010939.db
```

## Idempotence

Output of `make ansible-test` after the U6 apply:

```
== first run (changes allowed)
PLAY RECAP *********************************************************************
kg-control-1               : ok=71   changed=0    unreachable=0    failed=0    skipped=23   rescued=0    ignored=0   
kg-worker-1                : ok=39   changed=0    unreachable=0    failed=0    skipped=13   rescued=0    ignored=0   
kg-worker-2                : ok=39   changed=0    unreachable=0    failed=0    skipped=13   rescued=0    ignored=0   
== second run (must report changed=0 and failed=0 on every node)
kg-control-1               : ok=71   changed=0    unreachable=0    failed=0    skipped=23   rescued=0    ignored=0   
kg-worker-1                : ok=39   changed=0    unreachable=0    failed=0    skipped=13   rescued=0    ignored=0   
kg-worker-2                : ok=39   changed=0    unreachable=0    failed=0    skipped=13   rescued=0    ignored=0   
PASS  the second run reports no changes
```

## Limits

- **The key sits on the same node as etcd.** Encryption protects etcd snapshots and copies of the etcd disk. It does not protect against a compromised control-plane node, nor against anyone who may read Secrets through the API (the API decrypts for authorised callers). On EKS the key lives in KMS, outside the cluster. This is a weaker protection and the hardening report must say so.
- **The audit log is on the same node.** Someone with root on the node can change or delete it. It is not shipped elsewhere in Phase 2.
- **Request-level bodies of Pods can contain environment variable values.** Secrets must be passed as Secrets, not as `env.value`.
- **The `identity` provider stays last** so that old data can be read; new and rewritten Secrets use secretbox. Writing a plaintext Secret directly into etcd would still be readable by the API server.
- **No key rotation yet.** The steps are in the runbook; they have not been exercised.
- **A rebuild creates a new key.** Snapshots of an older cluster need the older key (the `.key-id` file names it, and each key has its own copy on the host).

## Acceptance

| Check (P2-U6: "Secret unreadable in etcd, audit log present") | Result |
|---|---|
| A Secret in etcd is not readable as plaintext | Pass: no plaintext value in the record, secretbox prefix present, every Secret record encrypted (tests and evidence above) |
| The API server still serves the decrypted value | Pass (test) |
| The audit log exists, is mode 600, and logs at the designed levels without Secret values | Pass (tests and evidence) |
| Rotation flags are set | Pass (evidence, first block) |
| The key has a copy outside the repository with restricted modes | Pass (evidence) |
| Restore from a snapshot works with encryption on | Pass (drill) |
| The role is idempotent | Pass |
