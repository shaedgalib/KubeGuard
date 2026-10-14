# ADR-002: Pod network (CNI) and kube-proxy replacement

Date: 2026-10-14
Status: accepted

## Context

The cluster is built with kubeadm and needs a pod network. Later phases need network policy enforcement (hardening), flow visibility for the dataset (Hubble), and an eBPF-capable data path for the eBPF detection work. Nodes have 2 GiB of RAM each, and carry a detachable second interface (`internet0`) during build windows. The pod CIDR is `10.244.0.0/16` and the service CIDR `10.96.0.0/16` (design decision D3).

## Options considered

1. **Cilium** with kube-proxy replacement. eBPF data path, network policy (including L7), Hubble flow visibility, built-in LoadBalancer address management and Gateway API.
2. **Calico.** Mature network policy; an eBPF data path exists as an option. Flow visibility and ingress would need further components.
3. **Flannel.** Simple overlay, but it does not enforce NetworkPolicy; a second component would be needed.

## Decision

Cilium 1.20.2, installed with Helm 4.3.0 from the host (`k8s/cilium/values.yaml`, pinned in `infra/versions.env`):

- `kubeProxyReplacement: true`; kube-proxy is skipped at `kubeadm init`. The agent is given the real API address `10.77.0.10:6443`.
- `ipam.mode: kubernetes` (pod ranges allocated by kubeadm), VXLAN tunnel between nodes.
- `devices: isolated0`, so the datapath never depends on the detachable `internet0` interface.
- Hubble relay and UI enabled; one operator replica.
- Kubernetes was set to 1.36.5 because Cilium 1.20 lists Kubernetes 1.33 to 1.36 only (see the amendments in `docs/specs/P1-cluster.md`).

## Consequences

- One component covers pod networking, Services, network policy, flow visibility, the layer 4 load balancer (ADR-003) and the layer 7 entry (ADR-004). Hubble gives the flow records used by the dataset work.
- Cilium has a hard Kubernetes version ceiling, so every Kubernetes upgrade needs a compatibility check first.
- Helm updates the Cilium ConfigMap without restarting the pods; `make cilium-restart` must follow every values change (found in P1-U6).
- Cilium is a single point of dependency: if it is broken, nodes are `NotReady`.
- Evidence: `docs/reports/P1-U5-cilium-evidence.md`.
