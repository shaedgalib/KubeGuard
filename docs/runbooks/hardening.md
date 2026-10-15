# Runbook: baseline hardening of the control plane and the nodes (P2-U2, P2-U6)

What the `hardening` Ansible role changes, how to apply and verify it, how to undo it, and how to handle the encryption key and the audit log. The role is part of `make ansible-apply`, so `make cluster` and `make rebuild` include it. In AWS terms: on EKS the provider sets most of these API server flags, ships the audit log to CloudWatch and encrypts Secrets with a KMS key. Here every one of them is set by hand, so every one has a test.

`node` below is the SSH helper from [lab-operations.md](lab-operations.md) (`node 10.77.0.10 '<command>'` runs a command on `kg-control-1`).

## What it changes

| Control | CIS checks | Where it is set |
|---|---|---|
| Anonymous requests are accepted only on `/livez`, `/readyz`, `/healthz` | 1.2.1 | `AuthenticationConfiguration` file, API server flag `--authentication-config`. The flag `--anonymous-auth=false` cannot be used: kubeadm's own probes of the API server are anonymous |
| Services with `externalIPs` are refused | 1.2.3 | Admission plugin `DenyServiceExternalIPs` |
| Profiling endpoints off | 1.2.15, 1.3.2, 1.4.1 | `--profiling=false` on the API server, controller manager and scheduler |
| Service account tokens expire as requested | 1.2.30 | `--service-account-extend-token-expiration=false` |
| TLS 1.2 or newer, strong cipher suites | 1.2.29, 4.2.12 | API server flags `--tls-min-version`, `--tls-cipher-suites`; kubelet `tlsMinVersion`, `tlsCipherSuites` |
| The API server verifies the kubelet's certificate | 1.2.5 | Kubelet `serverTLSBootstrap: true` plus approved certificate requests, then `--kubelet-certificate-authority` |
| PID limit per pod, default seccomp profile | 4.2.13, 4.2.14 | Kubelet `podPidsLimit: 4096`, `seccompDefault: true` |
| File modes and owners | 4.1.1, 4.1.9, 1.1.12 | `kubelet.service` and `config.yaml` mode 600; `/var/lib/etcd` owned by `etcd:etcd`, mode 700 |
| Audit log with rotation (P2-U6) | 1.2.16 to 1.2.19, 3.2.1, 3.2.2 | Audit policy file, `--audit-log-*` flags |
| Secrets encrypted in etcd (P2-U6) | 1.2.27, 1.2.28 | `EncryptionConfiguration` (secretbox), `--encryption-provider-config` |

The values are the `hardening_*` variables in `infra/ansible/group_vars/all.yml`. The API server flags reach the cluster through the kubeadm configuration template (`roles/kubeadm_init/templates/kubeadm-config.yaml.j2`). Audit and encryption each have a switch: `hardening_audit_enabled` and `hardening_encryption_enabled` (both `true` by default).

## How the role works

- **New cluster.** `kubeadm init` uses the hardened configuration from the start. The role only checks the result.
- **Running cluster.** The role compares the checksum of `/etc/kubeadm/kubeadm-config.yaml` with `/etc/kubeadm/applied-config.sha256`. When they differ it runs `kubeadm init phase control-plane all --dry-run`, copies the current manifests to `/var/backups/kubeguard/manifests-<epoch>` on the control node, regenerates the three control-plane manifests (the kubelet restarts the pods), waits until the processes show the new flags and `/readyz` answers, stores the configuration in the cluster (`upload-config`, so nodes that join later start hardened) and records the checksum. A second run changes nothing.
- **Nodes** are hardened one at a time (`serial: 1`): file modes, the kubelet configuration (only the keys in `hardening_kubelet_settings` are merged; a copy of the old file stays next to it, name ending in `~`), a kubelet restart only when the file changed, and approval of the node's own serving-certificate request.
- **Secrets** that existed before encryption was switched on are rewritten once, so they are stored encrypted.

## Apply

Restore points first (lab rule). `make vms-snapshot` shuts the VMs down for a short time.

```bash
make vms-snapshot SNAP=pre-u2
make etcd-snapshot
make ansible-apply ANSIBLE_ARGS="-e hardening_audit_enabled=false -e hardening_encryption_enabled=false"     # U2 only
```

Then, for U6, a second restore point and the full role (both switches are on by default):

```bash
make vms-snapshot SNAP=pre-u6
make etcd-snapshot
make ansible-apply
```

The API server restarts, so the API is unreachable for a short time; the playbook waits up to 3 minutes for each step. Workloads on the workers keep running. The kubelets are restarted one node at a time, never together.

## Verify

```bash
make test-hardening                       # one test per control, all of them
make test-hardening CONTROL=audit         # one control: anonymous | external-ips | profiling | files | kubelet-tls |
                                          #   tls | pid-limit | seccomp | etcd-encryption | audit
make scan LABEL=after-u2                  # kube-bench and kubescape again
make scan-compare BEFORE=<baseline dir> AFTER=<after dir>
make audit-log-size                       # size and files of the audit log on the control node
make hardening-evidence                   # read-only evidence for encryption and audit (no secret values printed)
make ansible-test                         # the second run must change nothing
```

The tests were written first and run on the unhardened cluster, where every control failed. A pass therefore means the control is in place, not only that the check is lenient. After a hardening change also run the P1 checks: `make net-test-u6 net-test-u7 net-test-u8`.

## Roll back

From the smallest step to the largest. Steps 1 and 2, and the key restore below, are written from the design and have not been exercised yet; try them first with a restore point in place.

1. **One control-plane manifest.** On the control node copy the file back from the backup the role made, then make the next Ansible run notice the difference:
   ```bash
   node 10.77.0.10 'ls /var/backups/kubeguard/'
   node 10.77.0.10 'sudo cp /var/backups/kubeguard/manifests-<epoch>/kube-apiserver.yaml /etc/kubernetes/manifests/kube-apiserver.yaml'   # likewise the other two
   node 10.77.0.10 'sudo rm /etc/kubeadm/applied-config.sha256'
   ```
   The kubelet restarts the pod from the old file. Also revert the change in `group_vars/all.yml` or the template in git, or the next `make ansible-apply` hardens again.
2. **A kubelet configuration.** The role keeps the old `/var/lib/kubelet/config.yaml.<...>~` next to the new one. Copy it back and run `sudo systemctl restart kubelet`.
3. **The whole lab** to the restore point: `make vms-restore SNAP=pre-u2` (or `pre-u6`). The VM disks return to that moment, including the checksum files of the role.
4. **Cluster state only:** `make etcd-restore SNAPSHOT=<file>` ([etcd-restore.md](etcd-restore.md)).

## Kubelet serving certificates (CIS 1.2.5)

With `serverTLSBootstrap` a kubelet does not create its own serving certificate. It sends a request (a CSR for the signer `kubernetes.io/kubelet-serving`) and nothing approves it automatically. Until it is approved the kubelet serves a self-signed certificate, and an API server that verifies kubelets cannot reach it: `kubectl logs`, `exec` and `port-forward` fail with an x509 error.

- The role approves **only** requests from the node's own identity (`system:node:<name>`) and then checks that the kubelet serves a certificate that chains to the cluster CA for the node address. On a running cluster the API server gets `--kubelet-certificate-authority` only after all three nodes pass. On a new cluster the flag is set from the start, and the role approves each node's request as it hardens that node.
- A node that joins later (rejoin drill, new worker) needs the same step: `make ansible-apply ANSIBLE_ARGS="--limit <node>"`. The rejoin drill approves its request itself.
- **Renewal.** Before the certificate expires the kubelet sends a new request. It stays `Pending` until someone approves it; the old certificate keeps working until it expires. Look now and then:
  ```bash
  make kubectl ARGS="get csr"
  make kubectl ARGS="describe csr <name>"          # requestor must be system:node:<node>, names must be that node's
  make kubectl ARGS="certificate approve <name>"
  ```
  Never approve everything in one command (`get csr -o name | xargs ... approve`): that would also approve requests from anyone else who can create CSRs, which is what this check is meant to prevent.

## Encryption key (P2-U6)

- **On the node:** `/etc/kubernetes/encryption/encryption-config.yaml` (root, mode 600) holds the key. The role generates it on the first run with `openssl rand -base64 32` and never prints or logs it. The API server reads it through a read-only mount.
- **Copy on the host:** `~/.local/share/kubeguard/encryption-keys/kg-control-1-<12 hex characters>.yaml` (directory 700, file 600), one file per distinct key. The 12 characters are the start of the file's checksum. It is outside the repository: never commit it, never paste it into a chat or a log.
- **Snapshots do not contain the key.** `make etcd-snapshot` saves `etcd-<time>.key-id` next to the snapshot, which names the key (the same 12 characters). The key copy stays in its own directory, so one stolen folder does not give both the data and the key.
- **A rebuild creates a new key.** `make reset` destroys the node, and the next `make cluster` generates a new key. Snapshots of the old cluster need the old key, which is why each key has its own file on the host.
- **Restore with another key.** `make etcd-restore` warns when the snapshot's key differs from the node's. To read such a snapshot put the old key's file in place and restart the API server:
  ```bash
  node 10.77.0.10 'sudo cp /etc/kubernetes/encryption/encryption-config.yaml /root/encryption-config.current'     # keep the current one
  cat ~/.local/share/kubeguard/encryption-keys/kg-control-1-<id>.yaml | node 10.77.0.10 'sudo tee /etc/kubernetes/encryption/encryption-config.yaml >/dev/null'
  node 10.77.0.10 'sudo chmod 600 /etc/kubernetes/encryption/encryption-config.yaml; sudo crictl stop $(sudo crictl ps --name kube-apiserver -q)'
  ```
  The kubelet starts the API server again, and it reads the file. After this, new Secrets are written with the old key; rebuild the cluster when you no longer need the old state.
- **Check by hand** that a Secret is encrypted: `etcdctl get /registry/secrets/<namespace>/<name> --print-value-only | head -c 40` (run through `crictl exec` in the etcd container, as `infra/hardening/test.sh` does) must start with `k8s:enc:secretbox:v1:key1:`. `make test-hardening CONTROL=etcd-encryption` does this and also searches the whole record for the plaintext value.
- **Not covered:** key rotation. A rotation adds a new key at the top of the list, restarts the API server, rewrites all Secrets (`kubectl get secrets -A -o json | kubectl replace -f -`) and removes the old key later.

What this protects and what it does not. The key sits on the same node as etcd. Encryption therefore protects etcd snapshots and copies of the etcd disk, not a compromised control-plane node and not anyone who may read Secrets through the API (the API decrypts them for authorised callers). On EKS the key lives in KMS, outside the cluster; here the protection is weaker, and the report says so.

## Audit log (P2-U6)

- **Where:** `/var/log/kubernetes/audit/audit.log` on `kg-control-1` (root, mode 600), written by the API server. The policy is `roles/hardening/files/audit-policy.yaml`, installed as `/etc/kubernetes/audit/audit-policy.yaml`.
- **Levels** (the first matching rule wins): Secrets, ConfigMaps, service account tokens and token reviews at `Metadata` (who, what, when, never the content); writes to pods, workloads, RBAC, network policies, webhooks, CRDs, certificates and the Gateway and Kyverno objects at `Request` (the body is kept); health URLs, leases, node status, component traffic, Cilium churn, endpoints and events not logged; everything else at `Metadata`.
- **Rotation:** `--audit-log-maxage=30` (days), `--audit-log-maxbackup=10`, `--audit-log-maxsize=100` (MB per file). The log therefore stays below about 1.1 GB. Check with `make audit-log-size` and `node 10.77.0.10 'df -h /var/log'`.
- **Reading it:**
  ```bash
  node 10.77.0.10 "sudo jq -c 'select(.verb==\"create\" and .objectRef.resource==\"pods\") | {user:.user.username, ns:.objectRef.namespace, name:.objectRef.name, code:.responseStatus.code}' /var/log/kubernetes/audit/audit.log | tail"
  ```
- **Caution:** at `Request` level a Pod's body is logged, and that includes plain environment variable values. Keep secrets in Secrets, not in `env.value`.

## If something goes wrong

| Symptom | Check |
|---|---|
| The API server does not come back after the apply | `node 10.77.0.10 'sudo crictl ps -a --name kube-apiserver'`, then `sudo crictl logs <id>`. Usual causes: a flag typo, or a file the flag points to is missing or unreadable (audit policy, encryption or authentication config). Roll back step 1 above |
| The kubelet does not start after the merge | `node <ip> 'sudo journalctl -u kubelet -n 50'`; roll back step 2 above |
| `kubectl logs` or `exec` fails with an x509 error | A serving-certificate request is pending: `make kubectl ARGS="get csr"`, approve the node's own request |
| Pods on a worker cannot be created after the apply | `make kubectl ARGS="describe pod <pod>"`. A pod that sets its own seccomp profile is unaffected; a PID limit of 4096 can stop a pod that forks heavily |
| `make ansible-test` shows a change on the second run | Read the task that changed. The role is meant to change nothing on a second run, so this is a bug in the role |
| A rejoined or new worker has file mode 644 on `config.yaml` | `kubeadm join` rewrites the file: `make ansible-apply ANSIBLE_ARGS="--limit <node>"` |

## Limits

- One control-plane node and one etcd member; the audit log lives on that node. Someone with root on the node can change or delete it. Shipping the log off the node is not part of Phase 2.
- Anonymous access remains on the three health paths by design.
- Findings that were accepted instead of fixed, each with its reason, are in the U2 report ([P2-U2-cis-fixes.md](../reports/P2-U2-cis-fixes.md)).
