# P1-U4 evidence: kubeadm init and join

> Note: This report describes the first build on Kubernetes 1.37.1. On 2026-10-10 the cluster was rebuilt on Kubernetes 1.36.5 because Cilium 1.20 lists Kubernetes 1.33 to 1.36 only (see the P1 spec amendments); the procedure and checks are unchanged.
Date: 2026-10-09 to 2026-10-10. Branch: `feat/p1-nodes`.

Design (approved by the researcher before the run): Kubernetes 1.37.1 from the official apt repository `pkgs.k8s.io` (packages `kubelet`, `kubeadm`, `kubectl` at 1.37.1-1.1, held), signing key checked against the pinned fingerprint `DE15 B144 86CD 377B 9E87 6E1A 2346 54DA 9A29 6436` (the key expires 2026-12-29). API at `10.77.0.10:6443`, each kubelet started with `--node-ip` set to the node's isolated address, pod CIDR `10.244.0.0/16`, service CIDR `10.96.0.0/16`, `addon/kube-proxy` skipped (Cilium replaces it in P1-U5), cgroup driver `systemd`. The pause image kubeadm expects (`registry.k8s.io/pause:3.10.2`) equals containerd's default, so nothing needed aligning.

## Runs

```
ansible-playbook site.yml (first full run)  : control plane initialised, both workers joined;
                                              one check task failed because of quoting in my jsonpath argument
run after the fix                           : changed=0 failed=0 on all three nodes
make ansible-test (two runs)                : second run changed=0 failed=0 on all three nodes
PASS  the second run reports no changes
```

## Independent check from the host, with the project kubeconfig only

```
kubeconfig ~/.kube/kubeguard.kubeconfig: mode 600, outside the repository
curl -k https://10.77.0.10:6443/readyz   -> ok
Server Version: v1.37.1

NAME           STATUS     ROLES           VERSION   INTERNAL-IP
kg-control-1   NotReady   control-plane   v1.37.1   10.77.0.10
kg-worker-1    NotReady   <none>          v1.37.1   10.77.0.11
kg-worker-2    NotReady   <none>          v1.37.1   10.77.0.12

kube-system: etcd, kube-apiserver, kube-controller-manager, kube-scheduler Running (1/1)
             coredns x2 Pending (no pod network yet)
kube-proxy daemonset: NotFound (as intended)
```

`NotReady` and `Pending` are the expected state until a CNI is installed (P1-U5). The host's default kubeconfig `~/.kube/config` was not read or modified; every command named the project kubeconfig explicitly (`make kubectl ARGS="..."` does this).

## Defects and notes

- The first node-address check split a `jsonpath` argument on spaces and failed. It now runs as a shell command with proper quoting. Init and join had already succeeded; the re-run skipped them, which also showed the "run only when not done" logic works.
- The host `kubectl` is v1.35.7 while the server is v1.37.1. That is outside kubectl's supported skew of one minor version. Basic commands work; a matching client (or the `kubectl` on `kg-control-1`) is advisable.

Result: the acceptance check of P1-U4 (3 nodes join, API reachable) passes, and the roles are idempotent.
