# Runbook: network policies and mutual TLS (P2-U5, P2-U8)

How the CiliumNetworkPolicies are tried, enforced and checked, and how mutual TLS between two services is switched on and verified. In AWS terms: the policies are what security groups for pods or Kubernetes NetworkPolicies do on EKS, written for Cilium so that Hubble can show every verdict; ztunnel mutual TLS is the job of a service mesh (App Mesh, Istio) or of Nitro encryption in transit plus mTLS in the application.

Lab rules still apply: take `make vms-snapshot SNAP=<label>` and `make etcd-snapshot` before changing the network layer. Attacks stay on the isolated network.

## What is in place

| Item | Where | Command |
|---|---|---|
| Policies, one file per namespace: `sample`, `default`, `kyverno`, `local-path-storage`, `monitoring` | `k8s/policies/<namespace>.yaml` | `make policies-apply [NS="sample kyverno"]`, `make policies-remove` |
| Audit mode (drops are allowed and shown as `AUDIT`) | per pod, set through the Cilium agents | `make policies-audit-on`, `make policies-audit-off` |
| Who talks to whom (from Hubble) | `infra/network/flows.py` | `make flows [SINCE=5m] [NS=...] [VERDICT=AUDIT\|DROPPED]` |
| Enforcement and audit mode per pod | `infra/network/policies.sh status` | `make policies-status` |
| Tests | group `netpol` and `mtls` of `infra/hardening/test.sh` | `make test-hardening CONTROL=netpol`, `CONTROL=mtls` |
| ztunnel key material | host `~/.local/share/kubeguard/ztunnel-ca/`, Secret `kube-system/cilium-ztunnel-secrets` | `make ztunnel-secrets` |
| Mutual TLS demo | `k8s/mtls/demo.yaml` (created and removed by the test) | `make test-hardening CONTROL=mtls` |
| Evidence for the reports | `~/.local/share/kubeguard/evidence/p2-network-security/` | `make network-evidence` |

Not covered by a policy on purpose: `kube-system` (CoreDNS, Cilium, Hubble, the control plane), `cilium-secrets` and `scanners`. A policy for `kube-system` would have to admit every namespace to CoreDNS and the control plane to everything; that is the next iteration, not this one.

The policy files are **drafts by the assistant** (2026-10-16), derived from the flows Hubble showed. The unit plan makes the policies the researcher's own work: read every rule against the flows, change what you disagree with, then enforce.

## How the policies work in Cilium

- A policy that selects a pod and has an `ingress` or `egress` section turns that direction into **default deny** for the pod. `endpointSelector: {}` with `ingress: [{}]` and `egress: [{}]` is the default-deny of every pod in the namespace; further policies add what is allowed. Allows are the union of all policies that select a pod.
- An allow needs both sides: the sender's egress rule and the receiver's ingress rule, when both are default-deny (`frontend-to-backend` and `backend-from-frontend`).
- **Entities** stand for things that are not pods: `host` (the node the pod runs on), `remote-node` (the other nodes), `kube-apiserver` (the API server; the control-plane node is both `remote-node` and `kube-apiserver` seen from a worker), `ingress` (the Gateway's Envoy), `world` (anything outside the cluster). `make flows` prints identities with all their entity labels, joined by `+`.
- Traffic from the local kubelet to a pod (probes) is always allowed. `kubectl exec`, `logs` and `port-forward` do not go through the pod network and are not affected.
- Services are translated before the policy is checked, so a rule names the real destination and port: the API server is 6443, not the Service port 443.
- Hubble shows a verdict for every flow: `FORWARDED`, `DROPPED` (policy denied) or `AUDIT` (audit mode: it would be dropped).

## Rollout for P2-U5 (the method)

Run from the repository root on the branch, one command at a time. Do not run two `make` commands in parallel.

```bash
E=~/.local/share/kubeguard/evidence/p2-network-security; mkdir -p -m 700 $E

# 0. restore points (the snapshot shuts the VMs down for about two minutes)
make vms-snapshot SNAP=pre-p2-network
make etcd-snapshot

# 1. what talks to what today (read-only)
make flows SINCE=10m | tee $E/01-flows-before.md

# 2. try the policies in audit mode: create them with audit mode on, so nothing is dropped
make policies-audit-on NS="sample kyverno local-path-storage monitoring"
make policies-apply NS="sample kyverno local-path-storage monitoring"
make policies-status
sleep 240                                   # normal traffic: scrapes, probes, webhooks
make net-test-u7 && make net-test-u8        # more traffic through the Gateway and the API server proxy

# 3. what would have been dropped? Every row is an allow that is missing
make flows SINCE=5m VERDICT=AUDIT | tee $E/02-audit.md
```

If step 3 prints rows: decide for each one whether the traffic is legitimate. If yes, add an allow to `k8s/policies/<namespace>.yaml`, run `make policies-apply NS=<namespace>`, wait two minutes and look again with `SINCE=2m`. If it should not exist, leave it out: it will be dropped. Repeat until the table is empty (the header line says `Edges: 0`). A pod that restarts loses audit mode; run `make policies-audit-on NS=<namespace>` again.

```bash
# 4. enforce
make policies-audit-off NS="sample kyverno local-path-storage monitoring"
make policies-apply NS=default              # default is tested while enforced; the test creates its pods
make policies-status | tee $E/03-status-enforced.txt
sleep 90                                    # Prometheus needs a scrape or two to show a blocked target as down
make test-hardening CONTROL=netpol | tee $E/04-netpol.txt
make net-test-u6 && make net-test-u7 && make net-test-u8
make kubectl ARGS="delete -f k8s/tests/ --ignore-not-found"
```

If anything stops working after step 4, remove the policies of that namespace and look at the dropped flows:

```bash
make policies-remove NS=monitoring          # or NS=sample, or no NS for all of them
make flows SINCE=5m VERDICT=DROPPED
```

## Rollout for P2-U8 (mutual TLS)

```bash
make etcd-snapshot
make ztunnel-secrets                        # keys on the host, Secret in kube-system; nothing secret is printed
make cilium-install                         # Helm upgrade with encryption.type=ztunnel (image pull needs the internet window)
make cilium-restart                         # the agents restart one node at a time
make cilium-status
make kubectl ARGS="-n kube-system get daemonset ztunnel-cilium"
make test-hardening CONTROL=mtls | tee $E/05-mtls.txt
```

The test creates the namespace `mtls-demo` (a server on `kg-worker-1`, a client on `kg-worker-2`), captures traffic on the server's node with tcpdump, and reports:

1. Before enrolment: the client reaches the server and the capture shows the page in clear text (this proves the capture method can see it).
2. After `kubectl label namespace mtls-demo io.cilium/mtls-enabled=true`: the client still reaches the server, the page no longer appears on the wire, and the capture shows traffic on port 15008 (the tunnel).
3. A client in another, non-enrolled namespace can no longer reach the enrolled server.
4. After the label is removed, everything works in clear text again.

By hand: `kubectl label namespace <ns> io.cilium/mtls-enabled=true` enrols (existing pods too), the same with a minus sign after the label name disenrols; `make kubectl ARGS="get namespaces -l io.cilium/mtls-enabled=true"` lists enrolled namespaces.

## Finish

```bash
make test-hardening | tee $E/06-test-hardening.txt         # every group, about six minutes
make net-test-u6 && make net-test-u7 && make net-test-u8
make kubectl ARGS="delete -f k8s/tests/ --ignore-not-found"
make scan LABEL=after-network-security                     # about five minutes
make scan-compare BEFORE=after-access-control-20261016-132547 AFTER=<directory printed by make scan, after 'Saved in'> | tee $E/07-scan-compare.md
make network-evidence
```

## If something goes wrong

| Symptom | Check |
|---|---|
| A namespace stopped working after the policies | `make policies-remove NS=<namespace>`, then `make flows SINCE=5m VERDICT=DROPPED NS=<namespace>`: the rows are the missing allows |
| Prometheus targets are down, `net-test-u7` fails | Wait two scrape intervals first. Then `make flows NS=monitoring VERDICT=DROPPED`; the usual cause is an entity that differs from the draft (`host` against `remote-node`) |
| Kyverno admission is refused or times out | `make flows NS=kyverno VERDICT=DROPPED`; the API server must reach port 9443 of the admission controller (`remote-node` or `host`) |
| `helm upgrade` of monitoring or Kyverno stalls | Their hook pods run in the same namespace and need DNS and the API server; check `kubectl get pods` there and the dropped flows |
| `netpol` test says "audit mode is still on" | `make policies-audit-off` |
| `make cilium-install` waits and times out | `make kubectl ARGS="-n kube-system get pods"`; the ztunnel pods need the Secret (`make ztunnel-secrets`) and the image `quay.io/cilium/ztunnel` |
| mTLS test: no traffic on 15008 | Is the namespace labelled? Are both pods on nodes with a ztunnel pod? `make kubectl ARGS="-n kube-system get pods -o wide"` |
| The whole lab misbehaves after the Cilium change | `make vms-restore SNAP=pre-p2-network` returns the VMs to the state before this branch |

## Limits

- The drafts cover five namespaces. `kube-system`, `cilium-secrets` and `scanners` have no policy, and there is no cluster-wide default-deny: a namespace created without a policy file is open.
- The policies are layer 3 and 4. DNS names, HTTP paths and methods are not restricted (Cilium can do that with `rules.dns` and `rules.http`; a later step).
- An allow for `remote-node` admits every node, not only the API server: the nodes' processes share one identity.
- Audit mode is per pod and not persistent.
- ztunnel mutual TLS is beta in Cilium 1.20, TCP only, both ends enrolled, and in an enrolled namespace Hubble and port-based policies see the tunnel port 15008 instead of the application port (ADR-007).
