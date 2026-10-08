# ADR-001: Lab network isolation

Date: 2026-10-09
Status: accepted

## Context

All attack scenarios run inside the lab. The lab host is connected to a home LAN (`172.16.212.0/23`, `172.16.214.0/23`) and also runs Docker (`172.17.0.0/16` to `172.21.0.0/16`) and the default libvirt network (`192.168.122.0/24`). Lab guests must not reach the LAN. Guests also need packages and container images while the base image and cluster are built.

## Options considered

1. **Isolated network.** A libvirt network without a `<forward>` element. No NAT, no routing. Guests reach each other and the host bridge address only.
2. **NAT network with firewall rules.** Guests reach the internet through the host. Rules must block the LAN. Isolation depends on correct and persistent firewall configuration.
3. **Routed network.** Guests are reachable from the LAN. Rejected: contradicts the isolation requirement.

## Decision

- Lab guests attach only to the isolated network `kg-lab` (bridge `virbr-kg`, `10.77.0.0/24`, gateway `10.77.0.1`, DHCP `10.77.0.100-10.77.0.199`), defined in `infra/libvirt/kg-lab-net.xml`. The subnet does not overlap any range listed in Context.
- Internet access is provided only during build windows by a separate NAT network `kg-build`, defined when P0-U6 starts. A guest is attached to `kg-build` only while the base image or cluster components are built, and detached before any attack work. Guests used for attacks never hold an interface on `kg-build`.
- Isolation is verified by `infra/libvirt/test-isolation.sh`: host-side checks (no `<forward>`, subnet, no masquerade rule) and in-VM checks (peer reachable, LAN gateway unreachable, internet unreachable).

## Consequences

- Isolation does not depend on firewall rules for the attack network.
- Offline operation after the build: images and packages needed at runtime must be present before detaching from `kg-build`.
- A private registry or image preloading may be required in Phase 1.
- The `kg-build` definition and its test are deliverables of P0-U6. Until then the build-time policy is documented but untested.
