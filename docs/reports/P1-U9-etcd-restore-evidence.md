# P1-U9 evidence: etcd snapshot and restore drill

Date: 2026-10-15. Branch: `feat/p1-cluster-drills`. Kubernetes 1.36.5, single control-plane node `kg-control-1`, etcd image `registry.k8s.io/etcd:3.6.8-0`. Script: `infra/drills/etcd.sh`; procedure: `docs/runbooks/etcd-restore.md`.

Commands were run by the researcher in their own terminal (`make vms-snapshot`, `make drill-etcd`). The assistant ran only short read-only checks. A VM-level restore point (`<name>-clean-snapshot` for each node) was taken before the drill, as the lab rules require.

## What the drill does

1. Creates ConfigMap `drill-before` and takes an etcd snapshot (`etcdctl snapshot save` inside the etcd container), copies it to the host outside the repository.
2. Deletes `drill-before` and creates `drill-after`.
3. Restores the snapshot: builds a new data directory with `etcdutl snapshot restore` (member `kg-control-1`, peer URL `https://10.77.0.10:2380`), moves the `etcd` and `kube-apiserver` static pod manifests away, swaps the data directories (old data kept as `member.before-restore-<time>`), moves the manifests back, and waits for `/readyz`.
4. Checks the result.

## Result

```
Snapshot: HASH 27800d4b, REVISION 117973, TOTAL KEYS 841, TOTAL SIZE 30 MB, VERSION 3.6.0
          saved in 184 ms; copied to the host: 29802528 bytes (mode 600, directory mode 700)

PASS  configmap drill-before created
PASS  drill-before deleted, drill-after created
(restore)  API ready
PASS  drill-before is back (state as of the snapshot)
PASS  drill-after is gone
PASS  all nodes Ready
PASS  kube-system pods Running
```

Read-only checks afterwards: both drill ConfigMaps were removed by the script; `/etc/kubernetes/manifests` holds all four static pod manifests and `manifests-paused` is empty; `/var/lib/etcd` holds `member` and `member.before-restore-20261015-171942` (the data from before the restore); the wait pattern used by the script (`crictl ps --name '^etcd$|^kube-apiserver$'`) matches exactly the two containers it is meant to wait for.

## Findings

- The first attempt of the drill failed with "connection refused" because it started right after `make vms-snapshot` had restarted the nodes. `build-nodes.sh` reported a node as back once SSH answered, before the API server was ready. `snapshot`, `restore` and `resize` now also wait for `/readyz`, and the drill waits for the API before it starts. The cluster itself was healthy a minute later; nothing was changed by the failed attempt.
- The etcd version shown by the snapshot status (3.6.0) is the version recorded in the snapshot data; the running image is 3.6.8. The restore worked across both.
- The restore returns the cluster objects to the time of the snapshot. It was tested with ConfigMaps only; restoring a cluster that holds many workloads, and what happens to pods created after the snapshot, were not tested in this drill.

## Acceptance

| Check | Result |
|---|---|
| An etcd snapshot can be taken and kept outside the repository | Pass |
| Restore from the snapshot returns the cluster to the snapshot state (deleted object back, later object gone) | Pass |
| Nodes `Ready` and system pods `Running` after the restore | Pass |
| Steps in a runbook | Pass (`docs/runbooks/etcd-restore.md`) |

## Notes

- The restore time was not measured; the script prints no timings for it.
- The old data directory (`member.before-restore-*`) and the snapshot file remain; delete them when not needed. The snapshot contains all Secrets, so it stays outside git.
