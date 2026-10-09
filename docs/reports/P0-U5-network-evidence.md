# P0-U5 evidence: isolated network kg-lab

Date: 2026-10-09. Branch: `dev` (merge `92950e4`). Run by the researcher on the lab host.

Commands: `make net-up`, `make net-test`.

```
Network kg-lab defined from infra/libvirt/kg-lab-net.xml
Network kg-lab marked as autostarted
Network kg-lab started

PASS  network kg-lab is active
PASS  no <forward> element
PASS  subnet is 10.77.0.0/24
PASS  no NAT/masquerade rule for the lab subnet
SKIP  in-VM checks (pass <vmA-ip> <vmB-ip> <ssh-user> once VMs exist, P0-U6)
```

Result: host-side checks pass. In-VM checks (VM-to-VM reachability, no route to the LAN gateway, no internet) are pending the VMs created in P0-U6.

## In-VM checks (added after P0-U6)

Date: 2026-10-09. Branch: `feat/p0-u6`. Two clones of `kg-base` (`kg-t1` at 10.77.0.127, `kg-t2` at 10.77.0.179), 1 vCPU and 1 GiB RAM each, attached only to `kg-lab`. Created with `infra/libvirt/clone-test-vms.sh create`, tested with `infra/libvirt/clone-test-vms.sh test`.

```
PASS  network kg-lab is active
PASS  no <forward> element
PASS  subnet is 10.77.0.0/24
PASS  no NAT/masquerade rule for the lab subnet
PASS  VM A reaches VM B
PASS  VM A cannot reach LAN gateway 172.16.212.1
PASS  VM A cannot reach the internet
```

Result: all host-side and in-VM checks pass. The acceptance check for P0-U5 is met.

Notes from the run:
- A first attempt failed: clones booted with a new MAC address did not request DHCP, because the cloud-init network config of `kg-base` matches the original MAC. Each clone now receives its own cloud-init seed with a unique instance ID, so that the network config is regenerated.
- Clones also reset `/etc/machine-id`, so that they send different DHCP client identifiers and receive different addresses.
- The gateway check uses the default route of the host (`172.16.212.1`). The host has a second LAN route (`172.16.214.1`, Wi-Fi) that this test does not cover.
