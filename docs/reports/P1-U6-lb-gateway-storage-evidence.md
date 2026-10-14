# P1-U6 evidence: LoadBalancer addresses, Gateway API and storage

Date: 2026-10-14. Branch: `feat/p1-cluster-networking`. Kubernetes 1.36.5, Cilium 1.20.2, Gateway API CRDs v1.6.1 (standard channel), local-path-provisioner v0.0.37. The nodes were still in the build window (`internet0` attached) during this run; the isolation step is planned for the end of Phase 1.

Commands were run by the researcher in their own terminal; the assistant ran only short read-only checks from the host with the project kubeconfig.

Design (see the P1-U6 entry in `docs/specs/P1-cluster.md`): Cilium LB IPAM gives `LoadBalancer` Services an address from `10.77.0.200` to `10.77.0.220`; L2 announcements answer ARP for them on `isolated0` from the worker nodes; the Cilium Gateway API controller (embedded Envoy) handles layer 7; local-path gives the default StorageClass.

## Order of work

```
make gateway-api-crds     # CRDs first
make cilium-install       # helm upgrade with the new values
make cilium-restart       # needed, see "Finding" below
make cilium-lb            # pool and L2 policy
make storage-install
make net-test-u6
```

## Finding: Helm does not restart Cilium after a ConfigMap change

After `make cilium-install`, `cilium status` was `OK`, but L2 announcements and the Gateway controller were inactive:

- `curl http://10.77.0.200` failed with "No route to host"; `ip neigh` showed the address as `FAILED` (nobody answered ARP).
- No `cilium-l2announce-*` leases existed.
- The GatewayClass `cilium` showed `Accepted: Unknown` ("Waiting for controller").
- The agents' DaemonSet generation was unchanged, and an agent log line reported a configuration drift: `enable-l2-announcements actual=false expectedValue=true`.

Cause: the ConfigMap was updated but the pods kept running with the old settings. Fix: the new target `make cilium-restart` (rolling restart of the operator, agents and Envoy). After it, both symptoms were gone. `cilium-restart` is now part of the order of work after every change to `k8s/cilium/values.yaml`.

## Results after the restart

Layer 4:

```
service/lb-test   LoadBalancer   10.96.9.111   10.77.0.200   80:31485/TCP
curl http://10.77.0.200  ->  200
leases: cilium-l2announce-default-lb-test   holder kg-worker-2
CiliumLoadBalancerIPPool kg-lb-pool: DISABLED false, CONFLICTING False, IPS AVAILABLE 20 (before the Gateway took one)
```

Layer 7:

```
gateway/gw-test   cilium   ADDRESS 10.77.0.201   PROGRAMMED True
httproute/route-test   Accepted=True, ResolvedRefs=True
curl -i http://10.77.0.201  ->  HTTP/1.1 200 OK, server: envoy
leases: cilium-l2announce-default-cilium-gateway-gw-test   holder kg-worker-2
```

Storage:

```
storageclass local-path (default)   rancher.io/local-path   WaitForFirstConsumer
pvc/pvc-test   Bound   100Mi   RWO   local-path
pod/pvc-test   1/1 Running;  kubectl exec pvc-test -- cat /data/probe  ->  ok
```

Cilium after the restart: `Cilium: OK, Operator: OK, Envoy DaemonSet: OK, Hubble Relay: OK`, 3 of 3 agents and Envoy pods ready, 7 of 7 pods managed by Cilium.

Version check: the installed CRD carries the annotation `gateway.networking.k8s.io/bundle-version: v1.6.1` with channel `standard`; the local-path deployment runs `rancher/local-path-provisioner:v0.0.37`.

## Acceptance

| Check | Result |
|---|---|
| `LoadBalancer` Service gets an address from the pool and answers from the host | Pass (10.77.0.200, HTTP 200) |
| Gateway programmed, route accepted, request reaches the backend through Envoy | Pass (10.77.0.201, HTTP 200, `server: envoy`) |
| PVC binds on the default StorageClass and a pod writes and reads data | Pass |
| `cilium status` healthy | Pass |

## Notes

- Both Services are announced by the same worker (`kg-worker-2`) in this run. Which node holds a lease is not fixed; failover was not tested in this unit.
- Hubble flow capture for these paths is not part of this evidence.
- The test objects (`lb-test`, `gw-test`, `route-test`, `pvc-test`) are still in the `default` namespace; remove them with `kubectl delete -f k8s/tests/`.
