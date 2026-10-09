# P1 evidence: rebuild on Kubernetes 1.36.5

Date: 2026-10-10. Branch: `feat/p1-cluster-networking`.

Reason: Cilium 1.20 lists Kubernetes 1.33 to 1.36 only (not 1.37), so the cluster moved from 1.37.1 to 1.36.5 before the pod network is installed. Compatibility of the other components was checked first on the projects' own pages: containerd 2.3.6 supports Kubernetes 1.36; the Cilium, MetalLB and kube-prometheus-stack charts allow it; `kubeadm` 1.36.5-1.1 is in the repository with the same signing key; Helm 3.16.3 does not cover 1.36, so Helm 4.3.0 was installed (Helm 4.3.x supports 1.34 to 1.37), together with the Cilium CLI 0.20.1 and Hubble 1.20.2, each after a SHA256 check.

## Steps

1. Pins changed in `infra/ansible/group_vars/all.yml` and `infra/versions.env`: Kubernetes 1.36.5 (`1.36.5-1.1`), `crictl` 1.36.0 with its SHA256.
2. `make vms-destroy`, then `make vms`: three fresh nodes from the template, `make vms-test` 21 PASS, 0 FAIL.
3. `make ansible-apply` (run by the researcher): all plays finished with `failed=0` on the three nodes.
4. `make ansible-test`: second run `changed=0`, `failed=0` on all three nodes.

## State after the rebuild (read-only checks)

```
kubeconfig ~/.kube/kubeguard.kubeconfig: mode 600, refreshed by the rebuild
curl -k https://10.77.0.10:6443/readyz  -> ok
Server Version: v1.36.5 ; host kubectl 1.35.7 (one minor version behind: within the supported skew)

kg-control-1   NotReady   control-plane   v1.36.5   10.77.0.10
kg-worker-1    NotReady   <none>          v1.36.5   10.77.0.11
kg-worker-2    NotReady   <none>          v1.36.5   10.77.0.12

etcd, kube-apiserver, kube-controller-manager, kube-scheduler: Running
coredns x2: Pending (no pod network yet)
kube-proxy daemonset: NotFound (as intended)
kubeadm 1.36.5, crictl 1.36.0; kubeadm, kubelet held
images kubeadm expects: kube-*:v1.36.5, coredns v1.14.2, etcd 3.6.8-0, pause 3.10.2 (equals containerd's default)
```

Note: the first Ansible run output was not captured by the assistant; the end state above and the idempotence test confirm the result.

Result: the cluster runs Kubernetes 1.36.5 and is ready for Cilium (P1-U5).
