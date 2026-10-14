# ADR-004: Layer 7 entry (ingress)

Date: 2026-10-14
Status: accepted

## Context

Realistic web workloads need routing by host and path, and HTTP-level visibility. This resolves design decision D7. In AWS terms the role is that of an Application Load Balancer, or an in-cluster proxy behind a Network Load Balancer. The layer 7 proxy has no external address by itself and relies on the layer 4 entry (ADR-003).

## Options considered

1. **ingress-nginx.** Widely used, but the project is retired (its repository states best-effort maintenance until March 2026).
2. **Cilium Gateway API.** The Gateway API is the Kubernetes successor to Ingress; Cilium implements it with its embedded Envoy.
3. **Another Gateway API implementation** (a separate Envoy-based controller). Works, but adds pods and memory use for no gain here.

## Decision

Cilium Gateway API:

- Gateway API CRDs v1.6.1, standard channel, installed first from the pinned release (`make gateway-api-crds`).
- `gatewayAPI.enabled: true` in `k8s/cilium/values.yaml`; the GatewayClass is `cilium`.
- A Gateway receives its address from the pool of ADR-003.

## Consequences

- Envoy runs inside the Cilium agent, so no extra proxy pods are needed on 2 GiB nodes, and requests can be observed at HTTP level.
- Cilium requires `kubeProxyReplacement: true` and the CRDs to exist before the operator starts; the CRD version must stay within what the Cilium release supports.
- Only HTTP is covered here; TLS, TLSRoute and similar are not set up in P1-U6 and are added only if a scenario needs them.
- Evidence: `docs/reports/P1-U6-lb-gateway-storage-evidence.md` (Gateway programmed, route accepted, `server: envoy`, HTTP 200).
