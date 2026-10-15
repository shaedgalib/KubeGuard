# P1-U10 evidence: node drain, node failure and rejoin drills

Date: 2026-10-15. Branch: `feat/p1-cluster-drills`. Kubernetes 1.36.5, Cilium 1.20.2, workers `kg-worker-1` and `kg-worker-2` (5 GiB each). Script: `infra/drills/node.sh`; procedure: `docs/runbooks/node-failure.md`.

Commands were run by the researcher in their own terminal. The assistant ran only short read-only checks. Before the drills the leftover P1-U6 test objects were deleted (a bare Pod with no controller cannot be drained). The restore point for the whole lab is the VM snapshot `<name>-clean-snapshot` taken before the etcd drill (P1-U9). All times below were measured by the script.

## Drill 1: drain and uncordon (`kg-worker-2`)

```
workload pods on kg-worker-2 before: coredns x2, hubble-relay, hubble-ui, prometheus-operator,
  prometheus-...-prometheus-0, sample/frontend
PASS  kg-worker-2 cordoned (no new pods)
PASS  drain finished
PASS  no workload pods left on kg-worker-2
pods not Running while drained: hubble-ui (ContainerCreating), prometheus-...-0 (Pending)
PASS  kg-worker-2 schedulable again
PASS  all pods Running again after 32 s in total
PASS  kg-worker-2 Ready
```

The pods of Deployments (CoreDNS, Hubble, the operator, the sample frontend) moved to the other nodes. Prometheus stayed `Pending` for as long as the node was drained, because its `local-path` volume lives on that node, and ran again after the uncordon.

## Drill 2: node failure (`kg-worker-1`)

Hard stop of the VM (`virsh destroy`), then start.

```
PASS  node reported NotReady after 46 s
PASS  all Deployments fully available again 490 s after the power-off
INFO  eviction and rescheduling took 444 s after the node was reported NotReady
pods not Running while the node was down: ten pods Terminating (they ran on the failed node)
PASS  node reachable over SSH after 12 s (after the power-on)
PASS  node Ready again after 22 s
PASS  all pods Running again after 38 s
INFO  total drill time 528 s
```

Pods of Deployments were recreated on the other worker (the sample app, Grafana, CoreDNS, Hubble, the local-path provisioner, kube-state-metrics and the operators were among the ten that had run on the failed node). The recovery time includes the default 5 minute eviction toleration, which was not changed; how the 490 s divide between detection, eviction and starting the new pods was not broken down. Prometheus did not run on this node, so a volume-bound pod was not part of this run; the drain drill covers that case.

## Drill 3: remove the node and join it again (`kg-worker-2`)

The drill drains the node, deletes it from the cluster, runs `kubeadm reset -f`, removes `/etc/cni/net.d`, reboots the node, creates a new join command (`kubeadm token create --ttl 15m --print-join-command`) and joins with the node name and CRI socket used by the Ansible role.

First run: all steps passed up to the join (node object deleted, node back after the reboot, `kubeadm join` finished, node `Ready` after 60 s, node address `10.77.0.12`), then **FAIL**: Prometheus was still in `Init:0/1` when the script's 300 s wait ended. Read-only checks afterwards showed that it recovered by itself: Prometheus was scheduled onto the rejoined node at 12:40:31, its pod sandbox creation failed three times (12:42:01, 12:43:46, 12:45:30) with `plugin type="cilium-cni" failed (add): unable to create endpoint: Cilium API client timeout exceeded`, and it started at 12:46:00 and was `Running` (2/2). So the pods were placed on the node before its Cilium agent answered, and the retries back off. In that run ten workload pods had been on the node.

The drill was changed: it now also measures when the Cilium agent on the node is ready, and waits up to 600 s for the pods.

Second run (only Prometheus was on the node):

```
PASS  kg-worker-2 cordoned / drain finished / no workload pods left
PASS  node object deleted
PASS  node back after the reboot
PASS  kubeadm join finished
PASS  node Ready 11 s after the join
PASS  Cilium agent on kg-worker-2 ready 26 s after the join
PASS  node address is 10.77.0.12 (isolated network)
PASS  all pods Running again 31 s after the join (71 s in total)
```

The delay of the first run did not reproduce. Why it appeared only in the first run was not investigated; the likely difference is the number of pods scheduled onto the new node at once, which was not tested.

## Findings

- A node reports `Ready` before its Cilium agent answers its API, and a rejoined node is schedulable at once. Pods placed on it in that window can wait several minutes for their network. Mitigation noted in the runbook: cordon the node after the join and uncordon it once the agent is ready.
- Both CoreDNS replicas were on `kg-worker-2` at the start of drill 1. Losing that node would have interrupted DNS until the pods were recreated.
- After a hard node failure, the pods of the failed node show `Terminating` until the node returns; they were already replaced.
- The failure drill's `INFO` line first named a specific volume as an example for a node that did not host it; the text was made generic.

## Acceptance

| Check | Result |
|---|---|
| Drain moves the Deployment pods off a node and the node can be uncordoned | Pass |
| After a node crash the cluster recovers, and the node returns by itself | Pass |
| A removed node can be reset and joined again with a new token, with the right address | Pass (second run; first run's wait was too short) |
| Steps in a runbook | Pass (`docs/runbooks/node-failure.md`) |

## Notes

- Control-plane failure was not drilled: it has one node and one etcd member (see the etcd runbook and the VM snapshots).
- The failure drill was run once on one node; the times are single measurements, not averages.
