# Runbook: etcd snapshot and restore (P1-U9)

etcd holds the whole cluster state (objects, Secrets, configuration). This cluster has a single control-plane node and a single etcd member, so a snapshot is the only recovery path for lost or damaged cluster state. In AWS terms: on EKS the provider does this for you; here you do it yourself.

Snapshots contain every Secret. Before encryption at rest (P2-U6) they are in plain form; afterwards they are encrypted with the key on the node, and a snapshot is only readable with that key (see "The encryption key" below). They are copied to `~/.local/share/kubeguard/etcd-backups/` on the host (directory `700`, files `600`), never into the repository.

## When to use it

- Before risky changes (hardening in Phase 2, upgrades), as a cheap restore point next to the VM snapshots.
- After accidental deletion of cluster objects.
- As the drill in this runbook, to prove that restore works before it is needed.

A restore returns the cluster **objects** to the moment of the snapshot. It does not undo changes inside pods or on node disks (for example data in a `local-path` volume). Pods created after the snapshot disappear from the API; the kubelet then removes their containers.

## Take a snapshot

```bash
make etcd-snapshot
```

It runs `etcdctl snapshot save` inside the etcd container, prints `etcdutl snapshot status` (hash, revision, key count, size), copies the file to the host and removes the copy on the node. The last line names the file. Run it before any restore drill and keep the file.

## Restore a snapshot

Safety first: `make vms-snapshot` (a whole-VM restore point), because a failed restore can leave the control plane down.

```bash
make etcd-restore SNAPSHOT=~/.local/share/kubeguard/etcd-backups/etcd-<timestamp>.db
```

What it does on `kg-control-1` (single member, kubeadm static pods):

1. Uploads the snapshot and, with etcd still running, builds a new data directory with `etcdutl snapshot restore` (member name `kg-control-1`, peer URL `https://10.77.0.10:2380`, as in the etcd manifest).
2. Moves `etcd.yaml` and `kube-apiserver.yaml` out of `/etc/kubernetes/manifests/` so the kubelet stops both static pods.
3. Keeps the old data as `/var/lib/etcd/member.before-restore-<timestamp>` and puts the restored directory in place.
4. Moves the manifests back; the kubelet starts etcd and the API server again.
5. Waits until `/readyz` answers (up to 3 minutes).
6. Checks that the API can read the Secrets again. A wrong encryption key shows up here as a failure.

Before step 1 it compares the key named in the snapshot's `.key-id` file with the key on the node and warns when they differ.

The API is unreachable for roughly the time steps 2 to 5 take. Workloads on the workers keep running meanwhile.

Afterwards: `make kubectl ARGS="get nodes"`, `make cilium-status`, and check that the objects you expect are present. Delete the `member.before-restore-*` directory on the node when you no longer need it.

## The encryption key (P2-U6)

`make etcd-snapshot` saves `etcd-<time>.key-id` next to the snapshot. It holds the first 12 characters of the checksum of the node's encryption configuration, which is also the end of the key copy's file name in `~/.local/share/kubeguard/encryption-keys/` (`kg-control-1-<id>.yaml`). The key is not stored with the snapshot. A snapshot of a cluster that was later rebuilt can only be read with the old key; how to put it back is in [hardening.md](hardening.md), section Encryption key.

## The drill

```bash
make vms-snapshot      # restore point for the whole lab
make drill-etcd
```

The drill creates ConfigMap `drill-before` and Secret `drill-secret-before`, takes a snapshot, deletes both and creates `drill-after` and `drill-secret-after`, restores the snapshot, and then checks that `drill-before` is back, the Secret is back and decrypts to the original value, `drill-after` and `drill-secret-after` are gone, all nodes are `Ready` and the `kube-system` pods are `Running`. It prints `PASS` or `FAIL` for each check and leaves the snapshot file on the host.

## If a restore fails

- The API does not come back: look at the etcd container on the node: `sudo crictl ps -a --name etcd`, `sudo crictl logs <id>`. The old data is still in `/var/lib/etcd/member.before-restore-*`: stop the static pods (move the manifests out), move the old directory back to `member`, and start them again.
- Last resort: `make vms-restore` returns the whole lab to its clean VM snapshot (this loses everything after that snapshot).
- A restore taken from a snapshot of a different cluster does not work: certificates and the cluster identity differ.
- The restore ends with "Secrets cannot be read": the node's encryption key does not match the snapshot's. Put the key named in the `.key-id` file back ([hardening.md](hardening.md)), or restore the VM snapshots instead.

## Limits

- One control-plane node: no quorum handling is needed, and no multi-member restore steps are covered here.
- The snapshot is taken from the running etcd; there is no scheduled backup in this lab.
