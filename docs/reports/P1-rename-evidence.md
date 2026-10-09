# P1 evidence: rename of lab objects to the keyword naming scheme

Date: 2026-10-09. Branch: `feat/p1-nodes`. Naming rules: [docs/naming.md](../naming.md).

Host steps, in order:
1. Removed the old VMs (`kg-t1`, `kg-t2`, `kg-base`) with their disks and seeds.
2. Removed the old networks `kg-lab` and `kg-build` (they shared the range `10.77.0.0/24` with the new isolated network, so the old one had to go first).
3. Redefined the storage pool as `kg-storage-pool` on the same folder; `noble-base.img` was kept.
4. `make isolated-network-up` and `make internet-network-up` created `kg-isolated-network` (autostart, bridge `kg-isolated-br`) and `kg-internet-access-network` (bridge `kg-internet-br`).
5. Rebuilt the template with the renamed scripts instead of renaming it in place:
```
make template-vm-create          -> kg-template-vm provisioned, powered off after about 100 s
make template-vm-snapshot        -> Domain snapshot kg-template-clean-snapshot created
make template-vm-restore-test
  PASS  marker written after boot
  PASS  marker gone after revert (snapshot kg-template-clean-snapshot restores)
```
6. Isolation checks with two test VMs (`kg-test-1-vm`, `kg-test-2-vm`) cloned from the template:
```
PASS  network kg-isolated-network is active
PASS  no <forward> element
PASS  subnet is 10.77.0.0/24
SKIP  masquerade check (cannot read nft rules; needs sudo in a terminal)
PASS  VM A reaches VM B
PASS  VM A cannot reach LAN gateway 172.16.212.1
PASS  VM A cannot reach the internet
```

The test VMs were removed afterwards.

Defects found and fixed during this step:
- `test-isolation.sh` printed `PASS` for the masquerade check when `sudo` could not read the nft rules, because it only looked for the absence of a match. It now prints `SKIP` in that case. The check still has to be run once from a terminal where `sudo` works.
- `test-isolation-vms.sh` took the first DHCP lease of a VM, which can be a stale lease from before the machine-id reset. It now takes the newest lease of the VM's interface.
- `virt-clone` names the disks of the test VMs automatically (`kg-template-disk-clone*.qcow2`), which does not follow the naming rules. This only affects throw-away test VMs. The node script in P1-U1 will name disks explicitly.

Result: the renamed scripts and definitions work, the template and its snapshot are rebuilt, and isolation holds on the new network.
