# Runbook: etcd snapshot and restore (P1-U9)

etcd holds the whole cluster state (objects, Secrets, configuration). This cluster has a single control-plane node and a single etcd member, so a snapshot is the only recovery path for lost or damaged cluster state. In AWS terms: on EKS the provider does this for you; here you do it yourself.

Snapshots contain every Secret in plain form. They are copied to `~/.local/share/kubeguard/etcd-backups/` on the host (directory `700`, files `600`), never into the repository.

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

The API is unreachable for roughly the time steps 2 to 5 take. Workloads on the workers keep running meanwhile.

Afterwards: `make kubectl ARGS="get nodes"`, `make cilium-status`, and check that the objects you expect are present. Delete the `member.before-restore-*` directory on the node when you no longer need it.

## The drill

```bash
make vms-snapshot      # restore point for the whole lab
make drill-etcd
```

The drill creates ConfigMap `drill-before`, takes a snapshot, deletes `drill-before` and creates `drill-after`, restores the snapshot, and then checks that `drill-before` is back, `drill-after` is gone, all nodes are `Ready` and the `kube-system` pods are `Running`. It prints `PASS` or `FAIL` for each check and leaves the snapshot file on the host.

## If a restore fails

- The API does not come back: look at the etcd container on the node: `sudo crictl ps -a --name etcd`, `sudo crictl logs <id>`. The old data is still in `/var/lib/etcd/member.before-restore-*`: stop the static pods (move the manifests out), move the old directory back to `member`, and start them again.
- Last resort: `make vms-restore` returns the whole lab to its clean VM snapshot (this loses everything after that snapshot).
- A restore taken from a snapshot of a different cluster does not work: certificates and the cluster identity differ.

## Limits

- One control-plane node: no quorum handling is needed, and no multi-member restore steps are covered here.
- The snapshot is taken from the running etcd; there is no scheduled backup in this lab.
