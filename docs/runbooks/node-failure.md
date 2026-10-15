# Runbook: node drain, node failure and rejoin (P1-U10)

Three drills on a worker node, with the commands that run them and what to do by hand. In AWS terms: draining a node before replacing an instance in a node group, an instance that dies, and a replacement instance joining the group. Here you do each step yourself.

Only workers are used. The control plane has one node and one etcd member; recovering it is the etcd runbook ([etcd-restore.md](etcd-restore.md)) and the VM snapshots.

## Before the drills

- The cluster must be healthy: all nodes `Ready`, all pods `Running` (the drills check this and refuse to start otherwise).
- Remove the leftover test objects from P1-U6 (`make kubectl ARGS="delete -f k8s/tests/"`). A bare Pod with no controller (`pvc-test`) cannot be drained, and it would never be recreated after a node failure.
- A VM-level restore point exists from `make vms-snapshot` (`<name>-clean-snapshot`). A worker is also easy to rebuild with the rejoin drill.

## What to know first

- **A Deployment's pods move; a pod with a local-path volume does not.** Prometheus uses a `local-path` volume, which exists on one node only. While that node is drained or down, the Prometheus pod stays `Pending` ("volume node affinity conflict") and comes back when the node does. Grafana, the sample app and CoreDNS have no such volume and move.
- **Failure detection is not instant.** The control plane marks a silent node `NotReady` after a grace period, and the pods on it are evicted after the default 5 minute toleration. The drill prints the times it measured.
- **Check where CoreDNS runs.** Both replicas can be on one worker; losing that node interrupts DNS until they are recreated elsewhere.

- **A node reports `Ready` before its Cilium agent answers.** A rejoined node is schedulable at once, so pods can be placed on it while the agent is still starting. Their sandbox creation then fails with `Cilium API client timeout exceeded` and is retried with growing delays; in the first rejoin drill this delayed Prometheus by about 5.5 minutes after it was scheduled. It recovers by itself. To avoid it, cordon the node right after the join and uncordon it once `kubectl -n kube-system get pods -l k8s-app=cilium --field-selector spec.nodeName=<node>` shows the agent `Ready`.

## Drill 1: drain and uncordon

```bash
make drill-node-drain NODE=kg-worker-2
```

Cordons the node (no new pods), drains it (`kubectl drain --ignore-daemonsets --delete-emptydir-data`), checks that no workload pod is left on it, lists the pods that are not `Running` (expected: Prometheus), uncordons the node and waits until all pods are `Running` again.

By hand: `kubectl cordon <node>`, `kubectl drain <node> --ignore-daemonsets --delete-emptydir-data`, do the maintenance, `kubectl uncordon <node>`.

## Drill 2: node failure

```bash
make drill-node-fail NODE=kg-worker-1       # about 10 minutes
```

Powers the VM off with `virsh destroy` (a hard stop, like a crash), waits until the node is `NotReady`, waits until every Deployment is fully available again (pods recreated on the other worker), then powers the VM on and waits for SSH, for the node to be `Ready` and for all pods to be `Running`. It prints the elapsed times.

By hand: `virsh -c qemu:///system destroy <node>-vm`, watch `kubectl get nodes -w` and `kubectl get pods -A -o wide`, then `virsh -c qemu:///system start <node>-vm`. The node rejoins by itself: its kubelet keeps its credentials.

## Drill 3: remove a node and join it again

```bash
make drill-node-rejoin NODE=kg-worker-2
```

Drains the node, deletes it from the cluster, runs `kubeadm reset -f` on it, removes `/etc/cni/net.d` and reboots it (so no old network state remains), creates a new join command on the control plane (`kubeadm token create --ttl 15m --print-join-command`), joins the node with the same node name and CRI socket as the Ansible role, and waits until it is `Ready`, its Cilium agent is ready, it has its isolated-network address and all pods are `Running` (up to 10 minutes).

By hand: the same commands in that order. The kubelet node address comes from `/etc/default/kubelet` (`--node-ip`), which `kubeadm reset` does not remove.

## If a drill leaves the cluster in a bad state

- A node stays `NotReady`: `make vms-status`, `ssh` to it, `sudo systemctl status kubelet`, `sudo journalctl -u kubelet -n 50`.
- A node was powered off and not started: `virsh -c qemu:///system start <node>-vm`.
- A node stays cordoned: `kubectl uncordon <node>`.
- A rejoin failed halfway: run `sudo kubeadm reset -f` on the node and repeat from the join step, or use `make ansible-apply` (the join role joins any node without a `kubelet.conf`).
- Last resort: `make vms-restore` returns the whole lab to the clean VM snapshots.
