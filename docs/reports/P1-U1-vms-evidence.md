# P1-U1 evidence: three cluster node VMs

Date: 2026-10-09. Branch: `feat/p1-nodes`. Names: [docs/naming.md](../naming.md).

Nodes (from `infra/libvirt/nodes.conf`): `kg-control-1-vm` 10.77.0.10, `kg-worker-1-vm` 10.77.0.11, `kg-worker-2-vm` 10.77.0.12. Each has 2 vCPU, 2048 MiB, a 20 GiB thin disk, and two interfaces: `isolated0` on `kg-isolated-network` and `internet0` on `kg-internet-access-network`.

## make vms

```
reserved 10.77.0.10 / .11 / .12 (DHCP reservations on kg-isolated-network)
== creating kg-control-1-vm, kg-worker-1-vm, kg-worker-2-vm
reachable: kg-control-1 at 10.77.0.10
reachable: kg-worker-1 at 10.77.0.11
reachable: kg-worker-2 at 10.77.0.12
```

## make vms-test (21 PASS, 0 FAIL)

Per node: SSH reachable, hostname, 2 vCPUs, memory about 2048 MiB, root disk grown to 19 GiB (of 20 GiB, as reported by `df`), kernel BTF present (`/sys/kernel/btf/vmlinux`). Across nodes: machine-ids are unique; `kg-control-1` reaches both workers.

## make vms-snapshot

```
Domain snapshot kg-control-1-clean-snapshot created
Domain snapshot kg-worker-1-clean-snapshot created
Domain snapshot kg-worker-2-clean-snapshot created
back up: kg-control-1, kg-worker-1, kg-worker-2
```

## make vms-isolate

```
PASS  <node>: default route on isolated0 after isolation     (all three nodes)
PASS  <node>: internet0 detached                              (all three nodes)
PASS  network kg-isolated-network is active
PASS  no <forward> element
PASS  subnet is 10.77.0.0/24
SKIP  masquerade check (cannot read nft rules; needs sudo in a terminal)
PASS  SSH to VM A works
PASS  VM A reaches VM B
PASS  VM A cannot reach LAN gateway 172.16.212.1
PASS  VM A cannot reach the internet
```

## make vms-restore

All three nodes returned to `<name>-clean-snapshot`, the internet interface was back, and `make vms-test` again gave 21 PASS and 0 FAIL. In the build state the default route through `internet0` has the lower metric (100), and `isolated0` keeps a default route at metric 200.

## Defects found and fixed during the unit

- After isolation a node had no default route, because the isolated network's DHCP gives no gateway; kubeadm needs one. A default route via the host bridge (`10.77.0.1`, which does not forward) was added to the node network config, and the isolation step now checks for it.
- `ssh` inside `while read` loops consumed the loop input, so only the first node was reported as reachable. Fixed with `ssh -n`.
- The isolation test could report "cannot reach" results when SSH itself had failed, and relied on the SSH agent. It now uses the lab key and fails if SSH fails.

The masquerade check, which needs `sudo`, was run by the researcher in a terminal on 2026-10-09 (`make isolated-network-test`): `PASS  no NAT/masquerade rule for the lab subnet`, together with the three network checks.

Result: the acceptance check of P1-U1 (`make vms` creates 3 reachable VMs) passes, and the clean-snapshot reset path works.
