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
