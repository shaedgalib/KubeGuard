# P1-U5 evidence: Cilium with kube-proxy replacement, Hubble relay and UI

Date: 2026-10-10. Branch: `feat/p1-cluster-networking`. Kubernetes 1.36.5. Chart `cilium/cilium` 1.20.2 (pinned in `infra/versions.env`), Helm 4.3.0, settings in `k8s/cilium/values.yaml`.

Settings: `kubeProxyReplacement: true` with the API at `10.77.0.10:6443` (kube-proxy was skipped at `kubeadm init`), `ipam.mode: kubernetes` (the pod ranges kubeadm allocated from `10.244.0.0/16`), `devices: isolated0` (the datapath never attaches to the detachable `internet0`), VXLAN tunnel, Hubble relay and UI on, one operator. A quick offline render (`helm template`) showed all settings in Cilium's configuration before the install.

Installed with `make cilium-install` and `make cilium-status` by the researcher. The checks below were run by the assistant from the host with the project kubeconfig only.

## Nodes and pods

```
kg-control-1   Ready   control-plane   v1.36.5   10.77.0.10
kg-worker-1    Ready   <none>          v1.36.5   10.77.0.11
kg-worker-2    Ready   <none>          v1.36.5   10.77.0.12

cilium (3 of 3), cilium-envoy (3 of 3), cilium-operator (1), hubble-relay (1), hubble-ui (1): Running
coredns x2: Running (was Pending before Cilium)
```

## cilium status

```
Cilium: OK   Operator: OK   Envoy DaemonSet: OK   Hubble Relay: OK   ClusterMesh: disabled
DaemonSet cilium Desired 3 Ready 3/3 Available 3/3; cilium-envoy 3/3; operator 1/1; hubble-relay 1/1; hubble-ui 1/1
```

## Traffic through a Service (proves kube-proxy replacement)

A pod `web` (nginx) in namespace `demo`, pod address `10.244.2.29` (inside the pod CIDR), exposed as Service `web` (ClusterIP `10.96.75.214`, inside the service CIDR). A client pod resolved `web.demo.svc.cluster.local` to `10.96.75.214` through CoreDNS and fetched the nginx welcome page through the Service. No kube-proxy exists in the cluster.

## Hubble

```
Healthcheck (via localhost:4245): Ok     Connected Nodes: 3/3     Flows/s: 11.70
demo/client2 -> kube-system/coredns :53  to-endpoint FORWARDED (UDP)
demo/client2 -> demo/web:80   TCP SYN, SYN-ACK, ACK, ACK+PSH, ACK+FIN ... all FORWARDED
```

The namespace `demo` was deleted afterwards; no port-forward was left running.

## Notes

- The first client run printed no output: a pod that exits instantly can lose its output when `kubectl run --rm -i` attaches. A pod that runs a little longer streamed it.
- Cilium's own load-balancer IP assignment (LB IPAM) is on by default in the rendered configuration. This matters for P1-U6, where MetalLB or Cilium's built-in load balancing will be decided in the load-balancer ADR.

Result: the acceptance check of P1-U5 (`cilium status` healthy, flows visible) passes.
