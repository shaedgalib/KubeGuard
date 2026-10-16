# ADR-007: Mutual TLS between services with Cilium's ztunnel encryption

Date: 2026-10-16
Status: proposed (a draft by the assistant; the unit plan leaves the choice of the mTLS option to the researcher, so it becomes `accepted` when the researcher agrees and the verification in `make test-hardening CONTROL=mtls` has passed)

## Context

Decision H6 asks to evaluate Cilium's mutual authentication first, with Istio ambient and Linkerd as the alternatives, and to decide after reading the documentation for the pinned Cilium version (1.20.2). The documentation pages below were read on 2026-10-16. They are the assistant's reading and have not yet been checked by the researcher.

Findings that change the starting point of H6:

1. **Mutual authentication is deprecated.** The Cilium 1.20 upgrade notes mark "Mutual Authentication (Beta)" as deprecated in favour of ztunnel encryption, and the 1.21 development documentation says it was removed. It was also only authentication: the handshake runs out of band between agents, and the documentation says encryption has to be enabled separately with WireGuard or IPsec.
2. **Ztunnel transparent encryption is its successor in Cilium 1.20 (beta).** It gives layer 4 mutual TLS with encryption for pod-to-pod TCP traffic. A per-node ztunnel proxy (Istio's ambient-mode proxy, shipped by Cilium) takes the traffic of enrolled pods through iptables rules in the pod's network namespace and carries it between nodes in an HBONE tunnel on port 15008. Workload certificates are issued by a CA whose root is the Secret `cilium-ztunnel-secrets` (the internal CA mode) or by SPIRE. Enrolment is per namespace with the label `io.cilium/mtls-enabled=true`.
3. **Limits listed by the documentation:** both ends of a connection must be enrolled (enrolled to non-enrolled is unsupported); only TCP is covered; host-network pods cannot be enrolled; Cluster Mesh is not supported; and because the traffic is encrypted before it leaves the pod, layer 4 policies on enrolled pods do not see the application port, only 15008.
4. **Cost.** The chart asks for 512 Mi of memory per ztunnel pod by default and lets the pod run on every node, including the control-plane node, which here has about 2.9 GB in total.

## Options considered

1. **Cilium mutual authentication (SPIFFE/SPIRE).** Rejected: deprecated in the pinned version and removed in the next one; authentication only.
2. **Cilium ztunnel encryption (beta).** Native to the installed CNI, no new control plane, per-namespace opt-in, real mutual TLS with encrypted payloads. Beta, TCP only, both ends enrolled.
3. **Istio ambient mode.** The same ztunnel idea with a full mesh around it (istiod, a CNI plugin, optional waypoint proxies for layer 7). Generally available, richer policy, but a second control plane and a second CNI component next to Cilium, and more memory than the lab nodes have to spare. Its interaction with Cilium's kube-proxy replacement would have to be configured and tested.
4. **Linkerd.** Sidecar proxies with automatic mTLS. Simple model, but a proxy in every pod, and the terms under which stable releases are distributed would have to be checked before relying on it (not verified by the assistant).
5. **WireGuard transparent encryption.** Encrypts node-to-node traffic but carries no workload identity, so it is not mutual TLS between services.

## Decision (proposed)

Option 2, scoped to what the unit needs: **mutual TLS verified between two services in a dedicated namespace (`mtls-demo`)**, not enabled for the sample app or the monitoring stack.

- Cilium values (`k8s/cilium/values.yaml`): `encryption.enabled: true`, `encryption.type: ztunnel`, internal CA, the proxy kept off the control-plane node (`tolerations: []`) and sized at 128 Mi requested, 256 Mi limit.
- The key material is generated on the host by `make ztunnel-secrets`, kept outside the repository (directory 700, files 600), and stored as the Secret `cilium-ztunnel-secrets` (encrypted at rest since P2-U6).
- `k8s/mtls/demo.yaml` holds a server and a client on different workers. `make test-hardening CONTROL=mtls` enrols the namespace, captures traffic on the server's node, and shows: clear text before enrolment, no clear text and traffic on port 15008 after it, a non-enrolled client refused, and everything back to normal after disenrolment.

Why not enrol the real workloads now: the Gateway's Envoy (host network) and Prometheus are not enrolled, so enrolled pods behind them would stop answering; and for enrolled traffic Hubble and layer 4 policies see the tunnel, not the application flows, which matters for the Phase 3 and 4 data collection (see the consequences).

## Consequences

- The Cilium agents and the operator restart once when the setting is applied (`make cilium-install` then `make cilium-restart`).
- Mutual TLS is available per namespace, but it is a beta feature: expect changes in the next Cilium releases and re-check this ADR at every Cilium upgrade.
- **Visibility trade-off for the research.** In an enrolled namespace Hubble sees HBONE connections on port 15008 instead of the application flows, and port-based network policies do not match the application port. Detection that relies on network flows or payloads loses detail there; detection at the endpoint (eBPF in the kernel of the node, process and syscall events) is not affected. Which workloads of Phase 3 are enrolled is therefore an experiment variable and should be recorded with every run.
- The key material is a new secret to protect: a copy of the CA root on the host (`~/.local/share/kubeguard/ztunnel-ca/`) and the Secret in the cluster. Rotation is not set up (the certificates are valid for ten years; workload certificates are short-lived and issued from the CA).
- Enrolled-to-non-enrolled traffic fails by design. Enrolling a namespace that is reached through the Gateway or scraped by Prometheus needs those components enrolled as well, or another design (a waypoint, which this option does not offer).
- If the beta feature proves unstable, the fallback is to leave the setting on without enrolling any namespace (no effect), or to switch it off and document that mutual TLS was evaluated and not adopted.

## References (read on 2026-10-16; leads for the researcher to check, not verified)

- Cilium 1.20, Mutual Authentication (Beta), deprecation note in the 1.20 Upgrade Guide: https://docs.cilium.io/en/stable/network/servicemesh/mutual-authentication/mutual-authentication/ and https://docs.cilium.io/en/v1.20/operations/upgrade/
- Cilium 1.20, Ztunnel Transparent Encryption (Beta): https://docs.cilium.io/en/stable/security/network/encryption-ztunnel/
- Cilium blog, Native mTLS for Cilium (2026-03-23): https://cilium.io/blog/2026/03/23/native-mtls-cilium/
