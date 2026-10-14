# ADR-005: Persistent storage

Date: 2026-10-14
Status: accepted

## Context

The monitoring stack (P1-U7) and some workloads need persistent volumes. There is no cloud block storage. Nodes have 2 GiB of RAM and 20 GiB disks each, and the lab is rebuilt often, so the solution must be light and easy to reset. In AWS terms this is the role of EBS with a default StorageClass.

## Options considered

1. **local-path-provisioner.** Creates a folder on the node disk for each claim; minimal footprint.
2. **NFS.** Shared volumes, but needs a server and moves data off the nodes.
3. **Longhorn or Rook-Ceph.** Replicated storage; heavy for 2 GiB nodes and more than the lab needs.

## Decision

local-path-provisioner v0.0.37, installed from the pinned upstream manifest (`make storage-install`), with its StorageClass `local-path` marked as the default. Binding mode is `WaitForFirstConsumer`, reclaim policy `Delete`.

## Consequences

- Very small footprint and fast to rebuild.
- A volume lives on one node, so its pod is tied to that node; there is no replication and no data survives the loss of that node's disk. Acceptable because lab data is reproducible, and bulky or important data is exported outside the cluster.
- Size limits on a claim are not enforced by the provisioner.
- Evidence: `docs/reports/P1-U6-lb-gateway-storage-evidence.md` (PVC bound, pod wrote and read back a file).
