# Naming conventions

Every object created for the lab carries the prefix `kg` (KubeGuard) and ends in a keyword that says what type of object it is. Pattern: `kg-<role>[-<number>]-<type>`.

## Type keywords

| Keyword | Means | Example |
|---|---|---|
| `network` | A libvirt virtual network (virtual switch plus DHCP) | `kg-isolated-network` |
| `br` | The bridge device on the host that backs a network. The only abbreviation: Linux limits device names to 15 characters | `kg-isolated-br` |
| `vm` | A virtual machine (libvirt domain) | `kg-template-vm` |
| `disk` | The disk file of one VM | `kg-template-disk.qcow2` |
| `seed` | The cloud-init configuration disk used on first boot | `kg-control-1-seed.iso` |
| `snapshot` | A saved restore point of a VM | `kg-template-clean-snapshot` |
| `storage-pool` | The libvirt folder holding disks and seeds | `kg-storage-pool` |

## Role words

| Role | Means |
|---|---|
| `isolated` | No internet. The only network attacks may run on (`10.77.0.0/24`) |
| `internet-access` | NAT to the internet. Attached only while building (`10.78.0.0/24`) |
| `template` | The clean Ubuntu VM that every node is cloned from |
| `control` | A control-plane node (API server, etcd) |
| `worker` | A worker node (runs workloads) |
| `test` | Throw-away VMs used to test the network |

## Names in use

| Thing | Name |
|---|---|
| Isolated network and bridge | `kg-isolated-network`, `kg-isolated-br` |
| Internet-access network and bridge | `kg-internet-access-network`, `kg-internet-br` |
| Storage pool | `kg-storage-pool` |
| Template VM, disk, snapshot | `kg-template-vm`, `kg-template-disk.qcow2`, `kg-template-clean-snapshot` |
| Cluster VMs | `kg-control-1-vm`, `kg-worker-1-vm`, `kg-worker-2-vm` |
| Kubernetes node hostnames | `kg-control-1`, `kg-worker-1`, `kg-worker-2` (the `-vm` suffix is dropped so that `kubectl get nodes` reads cleanly) |

## Old names

Earlier records (ADR-001, the P0 spec and the P0 evidence reports) use the names from Phase 0. They are kept as written, because they record what was true at the time.

| Phase 0 name | Current name |
|---|---|
| `kg-lab` | `kg-isolated-network` |
| `kg-build` | `kg-internet-access-network` |
| `virbr-kg`, `virbr-build` | `kg-isolated-br`, `kg-internet-br` |
| `kg-base`, `kg-base.qcow2`, `base-clean` | `kg-template-vm`, `kg-template-disk.qcow2`, `kg-template-clean-snapshot` |
| `kg-images` | `kg-storage-pool` |
| `kg-t1`, `kg-t2` | `kg-test-1-vm`, `kg-test-2-vm` |
| `make net-up`, `net-down`, `net-test` | `make isolated-network-up`, `isolated-network-down`, `isolated-network-test` |
| `make build-net-up`, `build-net-down` | `make internet-network-up`, `internet-network-down` |
| `make base-vm`, `base-snapshot`, `base-restore-test`, `base-destroy` | `make template-vm-create`, `template-vm-snapshot`, `template-vm-restore-test`, `template-vm-destroy` |
