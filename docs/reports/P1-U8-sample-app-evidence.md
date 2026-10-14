# P1-U8 evidence: sample application through the Gateway, flows in Hubble

Date: 2026-10-14. Branch: `feat/p1-cluster-monitoring-apps`. Kubernetes 1.36.5, Cilium 1.20.2. The nodes were still in the build window (`internet0` attached); isolation is planned for the end of Phase 1.

Commands were run by the researcher in their own terminal (`make sample-app-install`, `make net-test-u8`). The assistant ran only short read-only checks.

## What was deployed

Namespace `sample` (`k8s/sample-app/`): `frontend` (nginx; `/` answers `frontend ok`, `/api` is passed to the backend), `backend` (nginx serving `backend ok`), both on `nginx:1.27-alpine` with a 16 Mi memory request; a Gateway `sample-gw` (class `cilium`) and an HTTPRoute `sample-route` sending `/` to the frontend. Path: host, Gateway (Cilium Envoy), frontend, backend.

Placement in this run: `backend` on `kg-worker-1`, `frontend` on `kg-worker-2`, so the frontend to backend call crosses nodes through the VXLAN overlay.

## Result

```
Gateway address: 10.77.0.202            (from the pool 10.77.0.200-220)
PASS  GET /     -> frontend             ("frontend ok")
PASS  GET /api  -> backend              ("backend ok")
```

Hubble (`hubble observe --namespace sample`, run in each Cilium agent pod), all verdicts `FORWARDED`:

```
10.77.0.1:48896 (ingress) -> sample/frontend:80   http-request   (HTTP/1.1 GET http://10.77.0.202/api)
sample/frontend -> sample/backend:80              TCP SYN, SYN-ACK, ACK, PSH ... FIN   (via to-overlay and to-endpoint)
10.77.0.1:48896 (ingress) <- sample/frontend:80   http-response  (HTTP/1.1 200 1ms (GET http://10.77.0.202/api))
10.77.0.1:48892 (ingress) <- sample/frontend:80   http-response  (HTTP/1.1 200 0ms (GET http://10.77.0.202/))
```

The records come from the agent on the node that runs the frontend, so each agent shows only its own side of a flow. Layer 7 records (method, URL, status) appear for the Gateway leg because the traffic passes Envoy. The Gateway proxy's own connections to the frontend show as source `10.244.2.82` with the `(ingress)` label.

## Finding: the first test run failed on a race

The first run of `net-test-u8`, a few seconds after the pods became ready, returned `no healthy upstream` for both requests. A check some seconds later returned the correct answers; the route was `Accepted` and `ResolvedRefs` and both endpoints existed. Envoy had not yet learned the new endpoints. `k8s/sample-app/test.sh` now retries each request for up to 60 seconds.

## Acceptance

| Check | Result |
|---|---|
| Request from the host through the Gateway reaches the frontend and, via `/api`, the backend | Pass |
| Flows appear in Hubble with verdict `FORWARDED`, including HTTP records | Pass |

## Notes

- Flows were read from the agent pods; the Hubble UI and relay were not used for this evidence.
- The timings in the HTTP records (0 ms, 1 ms) are single requests and not a performance measurement.
- Remove the app with `make sample-app-remove`.
