# Runbook: access control, RBAC audit, Pod Security Admission and Kyverno (P2-U3, P2-U4, P2-U7)

How the three access controls of the branch `feat/p2-access-control` work, how to check them, and what to do when they block something. They are part of `make cluster`. In AWS terms: the RBAC audit is what IAM Access Analyzer does for IAM roles, Pod Security Admission is the built-in baseline that EKS also offers, and Kyverno plays the role of a policy engine such as OPA Gatekeeper on EKS or an SCP-style guardrail for what may run in the cluster.

Lab rules still apply: take `make vms-snapshot SNAP=<label>` and `make etcd-snapshot` before changing any of this.

## What is in place

| Control | Source of truth | Apply | Check |
|---|---|---|---|
| RBAC least privilege (P2-U3) | `k8s/monitoring/values.yaml` (Grafana, kube-state-metrics), `k8s/access/serviceaccounts.yaml`, `k8s/sample-app/` | `make monitoring-install`, `make access-apply` | `make rbac-audit`, `make test-hardening CONTROL=rbac` |
| Pod Security Admission (P2-U4) | `k8s/access/pod-security.conf` | `make access-apply` | `make psa-check`, `make test-hardening CONTROL=psa` |
| Kyverno policies (P2-U7) | `k8s/kyverno/values.yaml`, `k8s/kyverno/policies/` | `make kyverno-install`, `make kyverno-policies` | `make kyverno-status`, `make test-hardening CONTROL=kyverno` |

Decisions and reasons: [P2-U3 report](../reports/P2-U3-rbac-audit.md), [P2-U4 and U7 report](../reports/P2-U4-U7-admission-evidence.md), [ADR-006](../adr/ADR-006-kyverno-cel-policies.md).

## RBAC audit

```bash
make rbac-audit                       # read-only, markdown on the screen
make rbac-audit > /tmp/rbac.md        # keep a copy outside the repository
```

It lists roles with wildcards that are not built in, who holds sensitive capabilities (reading Secrets, creating pods, exec, escalate/bind/impersonate, nodes/proxy, approving CSRs, editing webhooks, creating service account tokens, creating volumes), who is bound to `cluster-admin`, and which default service accounts mount tokens. Every name and count comes from the API.

Read it for these changes: a new row under "Subjects outside kube-system", a new binding to `cluster-admin`, a role with a wildcard. The test `rbac` fails on the first two of those and on a wildcard role.

Two things the audit cannot see: rights that come from aggregated ClusterRoles added later, and rights granted to `system:authenticated`. Re-run it after installing any Helm chart, because charts bring their own ClusterRoles.

## Pod Security Admission

The level of every namespace is a line in `k8s/access/pod-security.conf` (enforce, audit, warn). `make access-apply` sets the labels, `make psa-check` compares them. Namespaces that do not exist yet are skipped, so run `make access-apply` again after creating one.

- **Add a workload namespace.** Create it, add `<name> restricted restricted restricted` to the table, run `make access-apply`.
- **A pod is rejected** with `violates PodSecurity "restricted:latest": ...`. The message names the fields. For `restricted` a container needs `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `runAsNonRoot: true` and the pod needs `seccompProfile.type: RuntimeDefault`. The sample app is an example (`k8s/sample-app/`).
- **See what would not pass before enforcing:** `kubectl label --dry-run=server --overwrite ns <name> pod-security.kubernetes.io/enforce=restricted` prints the pods that would violate it. Nothing is changed.
- **Exemptions** (privileged on purpose): `kube-system` and `cilium-secrets` (control plane, Cilium), `local-path-storage` (its helper pods mount host paths), `monitoring` (node-exporter needs the host namespaces and host paths), `scanners` (kube-bench needs hostPID and host paths). Each has `audit=restricted`, so the API audit log records the annotations of pods that would not pass.
- **Gap:** a namespace created without labels is not covered by Pod Security Admission. The Kyverno policies still apply to it. A cluster-wide default would close the gap (an `AdmissionConfiguration` for the API server); it is not done yet.

## Kyverno

Kyverno runs in the namespace `kyverno` (one replica per controller). The policies are `ValidatingPolicy` objects (CEL) with action `Deny`:

| Policy | Refuses | Scope |
|---|---|---|
| `disallow-privileged-containers` | any container, init container or ephemeral container with `securityContext.privileged: true` | every namespace except the system list |
| `require-resource-limits` | a container or init container without CPU and memory limits | same |
| `restrict-image-registries` | an image that does not come from docker.io, quay.io or registry.k8s.io (a name without a registry means docker.io) | same |

The system list is `kube-system`, `kube-public`, `kube-node-lease`, `cilium-secrets`, `local-path-storage`, `monitoring`, `scanners` and `kyverno`. It appears in the three policy manifests and in `config.webhooks` of `k8s/kyverno/values.yaml`; keep the four equal.

- **Read a refusal.** The message names the policy: `admission webhook "vpol.validate.kyverno.svc-fail" denied the request: Policy restrict-image-registries failed: ...`. A Deployment is refused when it is created (autogen). If you only see a Deployment with no pods, look at the events of its ReplicaSet (`kubectl -n <ns> describe rs`).
- **Allow another registry:** add it to `allowedRegistries` in `restrict-image-registries.yaml`, run `make kyverno-policies`, and add the reason to the report. **Exempt a namespace:** add it to the four lists and say why; the better fix is usually to make the workload comply.
- **Dry-run a manifest** against the policies without creating anything: `kubectl -n <ns> apply --dry-run=server -f file.yaml`.
- **Remove one rule:** `kubectl delete validatingpolicy <name>` (the file stays in the repository, `make kyverno-policies` brings it back).

### If Kyverno is down

`make drill-kyverno` shows both ways Kyverno can be away (about 70 seconds; it always starts Kyverno again):

| How it went away | What happens to workload namespaces | System namespaces |
|---|---|---|
| **Crash** (pod killed, node lost) | The policy webhook stays registered and fails closed (`failurePolicy: Fail`, 10 s): pod creation is **refused** until the replacement is ready (about 20 to 30 seconds in the drill) | Not affected |
| **Clean stop** (scale to zero) | Kyverno **removes its webhook configurations**, so the policies do **not apply**: a privileged pod is accepted in a namespace without Pod Security labels until Kyverno runs again (the drill shows it). Labelled namespaces such as `sample` still refuse it through Pod Security Admission | Not affected |

Look first: `make kyverno-status`, `kubectl -n kyverno logs deploy/kyverno-admission-controller`. Kyverno recreates its webhook configurations and policies by itself when it starts (about 30 seconds in the drill). The first install was delayed by a few minutes because a node's resolver failed a lookup; the pods recovered by themselves.

If the cluster must be unblocked at once (Kyverno will not start and the webhook still refuses), delete the webhook configuration. The drill does this and checks that pod creation works again and that Kyverno puts the webhook back:

```bash
make kubectl ARGS="delete validatingwebhookconfiguration kyverno-resource-validating-webhook-cfg"
```

Treat every planned stop (an upgrade, a scale to zero) as a window without the Kyverno policies, and do not create workloads in it.

### Roll back

`kubectl delete -f k8s/kyverno/policies/` removes the three rules. `helm -n kyverno uninstall kyverno` removes Kyverno (its CRDs stay). `make vms-restore SNAP=pre-p2-access` returns the whole lab to the state before this branch.

## Limits

- Kyverno 1.19 lists Kubernetes 1.33 to 1.35; the cluster runs 1.36 (ADR-006). The tests are the evidence; read the release notes before upgrading either.
- One admission controller replica: every restart is a short window in which the policies either refuse pod creation (crash) or do not apply (clean stop); see the table above.
- The monitoring namespace is exempt from every pod rule because of node-exporter. Moving node-exporter to its own namespace would let the rest of the stack be held to a stricter level.
- Policies check the pod spec at admission. They do not look at what an image does.
