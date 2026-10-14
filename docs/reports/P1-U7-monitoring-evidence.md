# P1-U7 evidence: monitoring with Prometheus and Grafana

Date: 2026-10-14. Branch: `feat/p1-cluster-monitoring-apps`. Kubernetes 1.36.5, Cilium 1.20.2. Chart `prometheus-community/kube-prometheus-stack` 92.6.0 (Prometheus Operator v0.94.1), pinned in `infra/versions.env`; settings in `k8s/monitoring/values.yaml`. The nodes were still in the build window (`internet0` attached).

Commands were run by the researcher in their own terminal; the assistant ran only short read-only checks.

## Node resize before the install

The nodes had 2 GiB each and the control plane showed 803 MiB available, so memory was raised before installing (`make vms-resize`, one node at a time, no rebuild):

| Node | Before | After | Available before | Available after resize |
|---|---|---|---|---|
| kg-control-1 | 2048 MiB | 3072 MiB | 803 MiB | 1684 MiB |
| kg-worker-1 | 2048 MiB | 5120 MiB | 1254 MiB | 4112 MiB |
| kg-worker-2 | 2048 MiB | 5120 MiB | 1247 MiB | 4113 MiB |

The host had 15408 MiB available before the resize. The new sizes are recorded in `infra/libvirt/nodes.conf`. All nodes returned `Ready` and `cilium status` stayed OK.

## Configuration

Alertmanager off; Prometheus retention 3 days and 4 GB, 5 GiB `local-path` volume; resource requests and limits on Prometheus, Grafana (768 Mi limit after the finding below), the operator, kube-state-metrics and node-exporter; the Grafana admin password comes from a Secret created in the cluster by `make monitoring-secret` (a random value, not in the repository); kube-proxy, etcd, scheduler and controller-manager targets are disabled (kubeadm binds the control-plane metrics to localhost, and Cilium replaces kube-proxy). The resource numbers are a starting point and have not been tuned.

## Result

```
release monitoring   deployed   kube-prometheus-stack-92.6.0   v0.94.1
pods (namespace monitoring): grafana 3/3, operator 1/1, kube-state-metrics 1/1,
  node-exporter x3 (one per node), prometheus 2/2 - all Running
pvc prometheus-...-db   Bound   5Gi   local-path
```

`make net-test-u7`:

```
Prometheus targets: 20 total, 0 down
PASS  no scrape target is down
PASS  at least one target is scraped
PASS  node metrics from all three nodes
PASS  Grafana health: database
Dashboard ConfigMaps loaded into Grafana: 24
PASS  dashboards provisioned
```

Memory with the monitoring stack running (read-only check, `free -m` on each node, same day):

| Node | Total | Used | Available |
|---|---|---|---|
| kg-control-1 | 2907 MiB | 1530 MiB | 1377 MiB |
| kg-worker-1 | 4917 MiB | 1329 MiB | 3588 MiB |
| kg-worker-2 | 4917 MiB | 1100 MiB | 3816 MiB |

Host: 31360 MiB total, 10266 MiB available. Prometheus ran on `kg-worker-2`, Grafana on `kg-worker-1`.

The researcher also opened Grafana through `make grafana-ui` (port-forward to port 3000) and signed in; the port-forward log shows the browser connections.

## Findings

- The first run of `net-test-u7` failed on every query because the Prometheus and Grafana images contain no `wget`, so the in-container requests could not run. The test was changed to query through the API server's Service proxy (`kubectl get --raw .../services/<name>:<port>/proxy/...`), which needs nothing in the pods.
- While the researcher browsed dashboards through the port-forward, the connection dropped ("connection reset by peer", "lost connection to pod"). `kubectl get pod` showed the `grafana` container with `restarts=1`, last state `OOMKilled`, exit code 137, at the same time. The first Grafana memory limit (384 Mi) was too small for dashboard browsing; it was raised to 768 Mi (request 256 Mi) in `k8s/monitoring/values.yaml` and applied with `make monitoring-install` (Helm revision 2; the live Deployment shows requests 256 Mi and limit 768 Mi, and the new pod had 0 restarts when checked). The other limits are unchanged and will be checked the same way if a pod restarts.
- The chart's own install notes name a Secret `monitoring-grafana`; with `existingSecret` the Secret used is `grafana-admin`, so those notes do not apply here.

## Acceptance

| Check | Result |
|---|---|
| All monitoring pods Running, volume bound | Pass |
| Prometheus scrapes its targets with none down, including all three nodes | Pass (20 targets, 0 down) |
| Grafana healthy with dashboards provisioned | Pass (database ok, 24 dashboard ConfigMaps) |

## Notes

- Dashboard contents (that panels show data) were looked at by the researcher in the browser and are not part of the scripted check.
- Cilium and Hubble metrics are not scraped yet; enabling them is a change to `k8s/cilium/values.yaml` followed by `make cilium-restart`, left for a later unit.
- Remove the stack with `make monitoring-uninstall`; the namespace, the Secret and the volume stay.
