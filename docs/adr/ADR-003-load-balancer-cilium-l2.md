# ADR-003: Layer 4 load balancer

Date: 2026-10-14
Status: accepted

## Context

A bare-metal cluster has no cloud load balancer, so Services of type `LoadBalancer` get no address. Attack scenarios include non-HTTP traffic (scans, DNS tunnelling, exfiltration), so a layer 4 entry is needed regardless of any HTTP gateway. All nodes share one network segment, `kg-isolated-network` (`10.77.0.0/24`, DHCP `.100-.199`, nodes `.10-.12`). In AWS terms this is the role of a Network Load Balancer.

## Options considered

1. **MetalLB** (L2 mode). The common choice and the default in the research plan; one extra component and its own speaker pods.
2. **Cilium LB IPAM with L2 announcements.** The same function inside the CNI already running (ADR-002).
3. **Host-level port forwarding or NodePort only.** No stable addresses; not representative.

## Decision

Cilium LB IPAM with L2 announcements:

- `k8s/cilium/lb-pool.yaml`: pool `10.77.0.200` to `10.77.0.220`, above the DHCP range and the node addresses.
- `k8s/cilium/l2-policy.yaml`: announce LoadBalancer addresses by ARP on `isolated0`, from worker nodes only. One node holds a lease per Service and answers ARP.
- `values.yaml`: `l2announcements.enabled`, `externalIPs.enabled`, a raised `k8sClientRateLimit` (leases raise the API request rate).

## Consequences

- No extra component to install, version or monitor; traffic stays on the one data path that Hubble observes.
- L2 announcement works only within one network segment, which holds for this lab. All traffic for an address enters through the node holding the lease, then eBPF spreads it to the pods; this is not a multi-node load balancer. Failover to another node was not tested in P1-U6.
- Moving to MetalLB later is possible: the Service API does not change.
- Evidence: `docs/reports/P1-U6-lb-gateway-storage-evidence.md` (address assigned from the pool, HTTP 200 from the host).
