# Runbook: access and inspect the KubeGuard cluster

Applies to the cluster built in P1-U4 (Kubernetes 1.37.1, three nodes). Written 2026-10-10.

## Rules

- Use only the project kubeconfig `~/.kube/kubeguard.kubeconfig` (mode 0600, outside the repository). Never use another kubeconfig for this cluster, and never use this one for anything else.
- Always go through `make kubectl ARGS="..."`. It clears `KUBECONFIG` and names the project file explicitly, so a stray environment variable cannot point `kubectl` at another cluster.
- The admin kubeconfig gives full administrator access. Do not copy it into the repository, chat or logs.

## Nodes

| Node | Address | Role |
|---|---|---|
| `kg-control-1` | 10.77.0.10 | control plane (API at `https://10.77.0.10:6443`) |
| `kg-worker-1` | 10.77.0.11 | worker |
| `kg-worker-2` | 10.77.0.12 | worker |

Shortcut for running a command on a node (lab key, no host-key prompts):

```bash
node() { ssh -i ~/.ssh/kubeguard-lab -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@"$@"; }
```

## Inspect the running cluster (read-only; checked by the researcher on 2026-10-10)

```bash
curl -sk https://10.77.0.10:6443/readyz; echo                # ok
make kubectl ARGS="version"                                   # Server Version: v1.37.1
make kubectl ARGS="get nodes -o wide"                         # 3 nodes, INTERNAL-IP 10.77.0.10 / .11 / .12
make kubectl ARGS="-n kube-system get pods"                   # etcd, apiserver, controller-manager, scheduler Running
make kubectl ARGS="-n kube-system get daemonset kube-proxy"   # NotFound: Cilium replaces kube-proxy
node 10.77.0.10 'cat /etc/kubeadm/kubeadm-config.yaml'        # the configuration kubeadm used
node 10.77.0.10 'kubeadm version -o short; apt-mark showhold' # v1.37.1; kubeadm, kubectl, kubelet held
node 10.77.0.11 'cat /etc/default/kubelet'                    # KUBELET_EXTRA_ARGS=--node-ip=10.77.0.11
```

State before the pod network is installed (P1-U5): nodes `NotReady`, CoreDNS `Pending`. This is expected.

Other useful read-only commands: `make kubectl ARGS="get pods -A -o wide"`, `make kubectl ARGS="describe node kg-worker-1"`, `make kubectl ARGS="get events -A --sort-by=.lastTimestamp"`.

## Rebuild the cluster

The normal way is Ansible. From the repository root, with the nodes running:

```bash
make ansible-apply     # applies every role; a finished cluster is left unchanged
make ansible-test      # runs the playbook twice; the second run must change nothing
```

To start from clean nodes: `make vms-destroy`, `make vms`, then `make ansible-apply`.

## Reset and rebuild by hand (reference; not yet run by hand by the researcher)

This removes only the Kubernetes state; the VMs, containerd and the packages stay. The steps follow what the roles do. If one fails, record the exact output and use the reset again.

```bash
# 1. reset each node, and drop the stale kubeconfig
node 10.77.0.10 'sudo kubeadm reset -f'
node 10.77.0.11 'sudo kubeadm reset -f'
node 10.77.0.12 'sudo kubeadm reset -f'
rm ~/.kube/kubeguard.kubeconfig

# 2. initialise the control plane (prints a join command; do not paste it anywhere)
node 10.77.0.10 'sudo kubeadm init --config /etc/kubeadm/kubeadm-config.yaml'

# 3. get the kubeconfig to the host
node 10.77.0.10 'sudo cat /etc/kubernetes/admin.conf' > ~/.kube/kubeguard.kubeconfig
chmod 600 ~/.kube/kubeguard.kubeconfig
make kubectl ARGS="get nodes"                                 # only kg-control-1, NotReady

# 4. create a short-lived join command, then run it on each worker
node 10.77.0.10 'sudo kubeadm token create --ttl 15m --print-join-command'
node 10.77.0.11 'sudo <join command> --node-name kg-worker-1 --cri-socket unix:///run/containerd/containerd.sock'
node 10.77.0.12 'sudo <join command> --node-name kg-worker-2 --cri-socket unix:///run/containerd/containerd.sock'

# 5. check
make kubectl ARGS="get nodes -o wide"                         # three nodes, all NotReady
make ansible-test                                              # PASS: Ansible agrees with the manual result
```

Installing `kubelet` and `kubeadm` by hand, if a node has no packages: add the `pkgs.k8s.io` v1.37 repository, check the key fingerprint is `DE15B14486CD377B9E876E1A234654DA9A296436`, install `kubelet=1.37.1-1.1` and `kubeadm=1.37.1-1.1` (plus `kubectl=1.37.1-1.1` on the control node), hold them, set `KUBELET_EXTRA_ARGS=--node-ip=<node address>` in `/etc/default/kubelet` and enable `kubelet`. The role `kubernetes_packages` is the exact reference.

## Known limits

- The host `kubectl` is v1.35.7 while the server is v1.37.1: two minor versions apart, outside the supported skew of one. Basic commands work; for anything unusual run `kubectl` on `kg-control-1` (`node 10.77.0.10 'sudo kubectl --kubeconfig /etc/kubernetes/admin.conf ...'`).
- The Kubernetes apt signing key expires on 2026-12-29. After that date a rebuild fails the fingerprint check until the pin in `infra/ansible/group_vars/all.yml` is updated.
