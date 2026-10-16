# ADR-006: Kyverno 1.19 with CEL-based policies on Kubernetes 1.36

Date: 2026-10-16
Status: accepted

## Context

Decision H4 of the Phase 2 spec asks for Kyverno to enforce rules that Pod Security Admission cannot: CPU and memory limits, a registry allowlist, and no privileged containers. Two facts found on 2026-10-16 shape how it is installed.

1. **Kubernetes version.** The cluster runs Kubernetes 1.36.5. That version was chosen because Cilium 1.20 lists Kubernetes 1.33 to 1.36 (ADR-002). The newest Kyverno release, 1.19 (chart 3.9.1, Kyverno v1.19.1), lists Kubernetes 1.33 to 1.35 on its releases page and says other versions "may work, but are not tested". Kubernetes 1.36 is therefore outside its tested range, and Cilium's ceiling and Kyverno's ceiling differ by one minor version.
2. **Policy type.** Kyverno 1.19 marks the classic `ClusterPolicy` and `Policy` types as deprecated and plans to remove them in 1.20 (estimated Oct or Nov 2026). The replacement is a set of CEL-based types in the API group `policies.kyverno.io` (`ValidatingPolicy` for validation).

## Options considered

1. **Kyverno 1.19.1 with `ValidatingPolicy` (CEL) on the current cluster.** Matches H4. Compatibility with 1.36 is not promised by the project, so it has to be shown by tests on this cluster.
2. **Kyverno 1.19.1 with `ClusterPolicy`.** Familiar syntax and many examples, but it would be written in a type that is removed in the next release.
3. **Kubernetes-native `ValidatingAdmissionPolicy` (CEL, built into the API server) without Kyverno.** No add-on, no webhook to keep alive, supported on every Kubernetes version we run. It departs from H4 and from the unit plan, which name Kyverno, and gives up Kyverno's reports and later policy types (mutation, generation, image verification).
4. **Downgrade the cluster to Kubernetes 1.35.** Inside Kyverno's range, but it means a rebuild and puts the cluster below Cilium's newest supported version for no gain in the lab.

## Decision

Option 1. Kyverno chart 3.9.1 (app v1.19.1), pinned in `infra/versions.env`, installed from the host with Helm (`make kyverno-install`, values in `k8s/kyverno/values.yaml`). The three policies are `ValidatingPolicy` objects in `k8s/kyverno/policies/`:

- `disallow-privileged-containers`, `require-resource-limits` (CPU and memory), `restrict-image-registries` (docker.io, quay.io, registry.k8s.io).
- Action `Deny`. Pod controllers (Deployments, DaemonSets, StatefulSets, Jobs, CronJobs) are covered by Kyverno's autogen, so a bad Deployment is refused when it is created.
- System namespaces are excluded twice: in the policies (`namespaceSelector`) and in the webhook configuration of the chart (`config.webhooks`), so a Kyverno outage cannot stop the control-plane add-ons or the monitoring stack from restarting.
- One replica of each controller and no cleanup controller, to save memory on the lab nodes.

The risk of running outside the tested range is handled by evidence instead of by assumption: every policy has a negative test and a positive test that run on this cluster (`make test-hardening CONTROL=kyverno`), and the P1 acceptance checks run after the install. The fallback, if a Kubernetes or Kyverno change breaks this, is option 3 with the same rules written as `ValidatingAdmissionPolicy` objects.

## Consequences

- The policies are written in the type that survives Kyverno 1.20.
- Kyverno is outside its tested Kubernetes range. A Kubernetes patch release or a Kyverno upgrade can change behaviour that the project does not test. The negative tests are the early warning, and `make cluster` runs them at the end.
- **A Kyverno outage has two faces, both measured by `make drill-kyverno`.** After a crash the policy webhook stays registered and fails closed (`failurePolicy: Fail`): pod creation in workload namespaces is refused until the replacement is ready (about 20 to 30 seconds in the drill). After a clean stop (scale to zero) Kyverno removes its webhook configurations, so its policies do not apply until it runs again; a privileged pod is then accepted in a namespace that has no Pod Security labels. Pod Security Admission keeps working in both cases, which is why the labelled namespaces keep a second layer. System namespaces are never affected. With one replica both windows exist at every restart of the admission controller.
- The registry allowlist and the limits rule apply to every namespace that is not on the exclusion list, including namespaces created later, whether or not they carry Pod Security labels.
- The exclusion list appears in four places (the three policy manifests and `config.webhooks` in the values file); they must be kept equal, and the values file says so.
- Upgrading Kyverno is a separate, tested step. Before the next minor version, read its release notes for Kubernetes 1.36 support.
- Evidence: `docs/reports/P2-U4-U7-admission-evidence.md`.
