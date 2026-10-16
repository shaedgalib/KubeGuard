# P2-U3 evidence: RBAC audit and least privilege

Date: 2026-10-16. Branch: `feat/p2-access-control`. Cluster: Kubernetes 1.36.5, three nodes. The audit and the changes were run by the assistant at the researcher's instruction ("go ahead"). The assistant did not produce any number in this report: every table below is the unchanged output of `make rbac-audit` or of `make test-hardening`; the paragraphs around them are the assistant's reading. Runbook: [access-control.md](../runbooks/access-control.md).

The unit plan leaves the choice of "which access is really needed" to the researcher. The decisions below were proposed by the assistant on 2026-10-16 and are open to change; a change is recorded here with its date.

## What was done

1. **A read-only audit** (`infra/rbac/audit.py`, `make rbac-audit`) that reads the roles, bindings, service accounts and pods from the API and prints, in the order of the CIS checks 5.1.1 to 5.1.13: roles with wildcards that are not built in, who holds each sensitive capability (and in which scope), who is bound to `cluster-admin`, and which default service accounts mount tokens.
2. **Three changes** that follow from the first audit run:
   - Grafana: the dashboard and data source sidecars watched ConfigMaps **and Secrets in all namespaces** through a ClusterRole. They now read ConfigMaps only, in the `monitoring` namespace, through a namespaced Role (`k8s/monitoring/values.yaml`).
   - kube-state-metrics: its default collector list included Secrets and ConfigMaps, which gave its service account list and watch rights on every Secret. Both collectors are removed; the dashboards do not use them.
   - Default service accounts: `automountServiceAccountToken: false` on the default service account of `sample` and `default`, and on the sample pods themselves (`k8s/sample-app/`, `k8s/access/serviceaccounts.yaml`).
3. **A test** (`make test-hardening CONTROL=rbac`) that fails if a wildcard role appears outside the built-in roles, if `cluster-admin` is bound to anything other than the two kubeadm groups, if Grafana or kube-state-metrics can list Secrets in all namespaces, or if the default service account of a workload namespace mounts a token. It was run before the changes: the two Secret checks and the two token checks failed, the other two passed (they guard against regressions).

## Decisions

| Finding in the first audit | Decision | Reason, and result |
|---|---|---|
| No role with a wildcard outside the built-in roles | Keep it that way | Guarded by the test `rbac` |
| `cluster-admin` bound to `system:masters` and `kubeadm:cluster-admins` | Accept | The admin kubeconfig and the cluster itself depend on them. The test fails on any other binding |
| Grafana: read ConfigMaps and Secrets in all namespaces | **Fixed** | Namespaced Role. What remains: the chart's Role still lists Secrets next to ConfigMaps, now only in the `monitoring` namespace (see the audit below). Narrowing that needs a post-render patch of the chart |
| kube-state-metrics: list and watch Secrets in all namespaces | **Fixed** | Collectors removed. The service account is gone from the table of sensitive subjects |
| Prometheus operator: read and write Secrets and ConfigMaps in all namespaces | Accept | The operator creates and updates the Secrets that hold the generated Prometheus configuration. The chart has no namespaced mode for its ClusterRole. Revisit if the operator is replaced |
| local-path-provisioner: create volumes, create pods | Accept | It creates a helper pod and a volume for every claim. The pod right is limited to its own namespace |
| `kube-apiserver-kubelet-client` with `system:kubelet-api-admin` | Accept | Built-in. It is the identity the API server uses to reach kubelets (logs, exec, node proxy) |
| Controllers and add-ons in kube-system (Cilium reads Secrets, controllers create pods, and so on) | Accept | Set by Kubernetes, kubeadm and the charts. Not changed by this unit |
| Default service accounts mount tokens | **Fixed** for `sample` and `default` | Nothing in those namespaces calls the API. The other namespaces keep the default: `kube-system`, `monitoring`, `local-path-storage` and `kyverno` run components that need their tokens |
| Kyverno (installed later in this branch, P2-U7): three new service accounts | Accept | They show up in the second audit. The admission controller may edit webhook configurations (it manages its own); all three read Secrets only in the `kyverno` namespace |

## Audit before the changes

Output of `make rbac-audit` on 2026-10-16, before any change of this unit. This was the first version of the script, which printed the scope of each role but not of each capability; its output is kept as it was printed.

<details>
<summary>Show the output</summary>

### RBAC audit

Kubernetes server v1.36.5. ClusterRoles: 79, Roles: 17, ClusterRoleBindings: 65, RoleBindings: 17, ServiceAccounts: 58.

#### Roles with wildcards (CIS 5.1.3)

Built-in roles with a wildcard (cluster-admin and the system:* controllers): 8.

Roles with a wildcard that are not built in: none.

#### Subjects outside kube-system that hold sensitive capabilities (CIS 5.1.1 to 5.1.13)

Includes users and groups other than the system:* groups, and ServiceAccounts of every namespace except kube-system, kube-public and kube-node-lease.

| Subject | Roles (scope) | Capabilities |
|---|---|---|
| Group:kubeadm:cluster-admins | ClusterRole/cluster-admin (cluster) | approve CSRs, create PVs, create SA tokens, create pods, edit webhooks, escalate/bind/impersonate, exec into pods, nodes/proxy, read Secrets, wildcard |
| Group:system:masters | ClusterRole/cluster-admin (cluster) | approve CSRs, create PVs, create SA tokens, create pods, edit webhooks, escalate/bind/impersonate, exec into pods, nodes/proxy, read Secrets, wildcard |
| ServiceAccount:local-path-storage/local-path-provisioner-service-account | ClusterRole/local-path-provisioner-role (cluster); Role/local-path-provisioner-role (namespace local-path-storage) | create PVs, create pods |
| ServiceAccount:monitoring/monitoring-grafana | ClusterRole/monitoring-grafana-clusterrole (cluster) | read Secrets |
| ServiceAccount:monitoring/monitoring-kube-prometheus-operator | ClusterRole/monitoring-kube-prometheus-operator (cluster) | read Secrets |
| ServiceAccount:monitoring/monitoring-kube-state-metrics | ClusterRole/monitoring-kube-state-metrics (cluster) | read Secrets |
| User:kube-apiserver-kubelet-client | ClusterRole/system:kubelet-api-admin (cluster) | escalate/bind/impersonate, nodes/proxy, wildcard |

#### Subjects in kube-system and the built-in system groups

These are the control-plane components, controllers and add-ons. Their rights are set by Kubernetes, kubeadm and the Helm charts.

| Subject | Capabilities |
|---|---|
| ServiceAccount:kube-system/bootstrap-signer | read Secrets |
| ServiceAccount:kube-system/certificate-controller | approve CSRs |
| ServiceAccount:kube-system/cilium | read Secrets |
| ServiceAccount:kube-system/cilium-operator | read Secrets |
| ServiceAccount:kube-system/clusterrole-aggregation-controller | escalate/bind/impersonate |
| ServiceAccount:kube-system/daemon-set-controller | create pods |
| ServiceAccount:kube-system/disruption-controller | wildcard |
| ServiceAccount:kube-system/generic-garbage-collector | approve CSRs, edit webhooks, exec into pods, nodes/proxy, read Secrets, wildcard |
| ServiceAccount:kube-system/horizontal-pod-autoscaler | wildcard |
| ServiceAccount:kube-system/job-controller | create pods |
| ServiceAccount:kube-system/namespace-controller | edit webhooks, exec into pods, nodes/proxy, read Secrets, wildcard |
| ServiceAccount:kube-system/persistent-volume-binder | create PVs, create pods |
| ServiceAccount:kube-system/replicaset-controller | create pods |
| ServiceAccount:kube-system/replication-controller | create pods |
| ServiceAccount:kube-system/resourcequota-controller | read Secrets, wildcard |
| ServiceAccount:kube-system/statefulset-controller | create pods |
| ServiceAccount:kube-system/token-cleaner | read Secrets |
| User:system:kube-controller-manager | create SA tokens, read Secrets, wildcard |

#### Bindings to cluster-admin (CIS 5.1.1, 5.1.7)

| Kind | Binding | Namespace | Subjects |
|---|---|---|---|
| ClusterRoleBinding | cluster-admin | - | Group:system:masters |
| ClusterRoleBinding | kubeadm:cluster-admins | - | Group:kubeadm:cluster-admins |

#### Default service accounts and token mounting (CIS 5.1.5, 5.1.6)

| Namespace | default SA automountServiceAccountToken | Pods using the default SA | Pods with a mounted API token |
|---|---|---|---|
| cilium-secrets | unset (token mounted) | none | 0 of 0 |
| default | unset (token mounted) | none | 0 of 0 |
| kube-node-lease | unset (token mounted) | 0 | 0 of 0 |
| kube-public | unset (token mounted) | 0 | 0 of 0 |
| kube-system | unset (token mounted) | 4 | 10 of 15 |
| local-path-storage | unset (token mounted) | none | 1 of 1 |
| monitoring | unset (token mounted) | none | 4 of 7 |
| sample | unset (token mounted) | backend-cdb6cbdd8-4chjp, frontend-bd7b6d57b-cr7tb | 2 of 2 |
| scanners | unset (token mounted) | none | 0 of 0 |

</details>

## Audit after the changes

Output of `make rbac-audit` after the monitoring upgrade, the default service account changes and the Kyverno install, with the final version of the script (the scope of each capability is in brackets).

### RBAC audit

Kubernetes server v1.36.5. ClusterRoles: 92, Roles: 21, ClusterRoleBindings: 70, RoleBindings: 21, ServiceAccounts: 63.

#### Roles with wildcards (CIS 5.1.3)

Built-in roles with a wildcard (cluster-admin and the system:* controllers): 8.

Roles with a wildcard that are not built in: none.

#### Subjects outside kube-system that hold sensitive capabilities (CIS 5.1.1 to 5.1.13)

Includes users and groups other than the system:* groups, and ServiceAccounts of every namespace except kube-system, kube-public and kube-node-lease. The scope of each capability is given in brackets: cluster, or the namespace it is limited to.

| Subject | Roles (scope) | Capabilities |
|---|---|---|
| Group:kubeadm:cluster-admins | ClusterRole/cluster-admin (cluster) | approve CSRs (cluster), create PVs (cluster), create SA tokens (cluster), create pods (cluster), edit webhooks (cluster), escalate/bind/impersonate (cluster), exec into pods (cluster), nodes/proxy (cluster), read Secrets (cluster), wildcard (cluster) |
| Group:system:masters | ClusterRole/cluster-admin (cluster) | approve CSRs (cluster), create PVs (cluster), create SA tokens (cluster), create pods (cluster), edit webhooks (cluster), escalate/bind/impersonate (cluster), exec into pods (cluster), nodes/proxy (cluster), read Secrets (cluster), wildcard (cluster) |
| ServiceAccount:kyverno/kyverno-admission-controller | ClusterRole/kyverno:admission-controller (cluster); ClusterRole/view (cluster); Role/kyverno:admission-controller (namespace kyverno) | edit webhooks (cluster), read Secrets (ns kyverno) |
| ServiceAccount:kyverno/kyverno-background-controller | ClusterRole/kyverno:background-controller (cluster); ClusterRole/view (cluster); Role/kyverno:background-controller (namespace kyverno) | read Secrets (ns kyverno) |
| ServiceAccount:kyverno/kyverno-reports-controller | ClusterRole/kyverno:reports-controller (cluster); ClusterRole/view (cluster); Role/kyverno:reports-controller (namespace kyverno) | read Secrets (ns kyverno) |
| ServiceAccount:local-path-storage/local-path-provisioner-service-account | ClusterRole/local-path-provisioner-role (cluster); Role/local-path-provisioner-role (namespace local-path-storage) | create PVs (cluster), create pods (ns local-path-storage) |
| ServiceAccount:monitoring/monitoring-grafana | Role/monitoring-grafana (namespace monitoring) | read Secrets (ns monitoring) |
| ServiceAccount:monitoring/monitoring-kube-prometheus-operator | ClusterRole/monitoring-kube-prometheus-operator (cluster) | read Secrets (cluster) |
| User:kube-apiserver-kubelet-client | ClusterRole/system:kubelet-api-admin (cluster) | escalate/bind/impersonate (cluster), nodes/proxy (cluster), wildcard (cluster) |

#### Subjects in kube-system and the built-in system groups

These are the control-plane components, controllers and add-ons. Their rights are set by Kubernetes, kubeadm and the Helm charts.

| Subject | Capabilities |
|---|---|
| ServiceAccount:kube-system/bootstrap-signer | read Secrets (ns kube-system) |
| ServiceAccount:kube-system/certificate-controller | approve CSRs (cluster) |
| ServiceAccount:kube-system/cilium | read Secrets (ns cilium-secrets) |
| ServiceAccount:kube-system/cilium-operator | read Secrets (cluster) |
| ServiceAccount:kube-system/clusterrole-aggregation-controller | escalate/bind/impersonate (cluster) |
| ServiceAccount:kube-system/daemon-set-controller | create pods (cluster) |
| ServiceAccount:kube-system/disruption-controller | wildcard (cluster) |
| ServiceAccount:kube-system/generic-garbage-collector | approve CSRs (cluster), edit webhooks (cluster), exec into pods (cluster), nodes/proxy (cluster), read Secrets (cluster), wildcard (cluster) |
| ServiceAccount:kube-system/horizontal-pod-autoscaler | wildcard (cluster) |
| ServiceAccount:kube-system/job-controller | create pods (cluster) |
| ServiceAccount:kube-system/namespace-controller | edit webhooks (cluster), exec into pods (cluster), nodes/proxy (cluster), read Secrets (cluster), wildcard (cluster) |
| ServiceAccount:kube-system/persistent-volume-binder | create PVs (cluster), create pods (cluster) |
| ServiceAccount:kube-system/replicaset-controller | create pods (cluster) |
| ServiceAccount:kube-system/replication-controller | create pods (cluster) |
| ServiceAccount:kube-system/resourcequota-controller | read Secrets (cluster), wildcard (cluster) |
| ServiceAccount:kube-system/statefulset-controller | create pods (cluster) |
| ServiceAccount:kube-system/token-cleaner | read Secrets (ns kube-system) |
| User:system:kube-controller-manager | create SA tokens (cluster), read Secrets (cluster), wildcard (cluster) |

#### Bindings to cluster-admin (CIS 5.1.1, 5.1.7)

| Kind | Binding | Namespace | Subjects |
|---|---|---|---|
| ClusterRoleBinding | cluster-admin | - | Group:system:masters |
| ClusterRoleBinding | kubeadm:cluster-admins | - | Group:kubeadm:cluster-admins |

#### Default service accounts and token mounting (CIS 5.1.5, 5.1.6)

| Namespace | default SA automountServiceAccountToken | Pods using the default SA | Pods with a mounted API token |
|---|---|---|---|
| cilium-secrets | unset (token mounted) | none | 0 of 0 |
| default | false | lb-test-dc75d7589-7qcz5, pvc-test | 0 of 2 |
| hardening-test | unset (token mounted) | none | 0 of 0 |
| kube-node-lease | unset (token mounted) | 0 | 0 of 0 |
| kube-public | unset (token mounted) | 0 | 0 of 0 |
| kube-system | unset (token mounted) | 4 | 10 of 15 |
| kyverno | unset (token mounted) | none | 4 of 4 |
| local-path-storage | unset (token mounted) | none | 1 of 1 |
| monitoring | unset (token mounted) | none | 4 of 7 |
| sample | false | backend-bd5794748-lm7vs, frontend-7586b48764-wljsw | 0 of 2 |
| scanners | unset (token mounted) | none | 0 of 0 |

## Test results

Part of the output of `make test-hardening` (the full run is in the P2-U4 and U7 report):

```
== RBAC least privilege (CIS 5.1.1 to 5.1.13, P2-U3)
PASS  no role with a wildcard exists outside the built-in roles
PASS  cluster-admin is bound to system:masters and kubeadm:cluster-admins only
PASS  monitoring-grafana cannot list Secrets in all namespaces
PASS  monitoring-kube-state-metrics cannot list Secrets in all namespaces
PASS  the default service account in sample does not mount an API token
PASS  the default service account in default does not mount an API token
== Pod Security Admission (P2-U4)
PASS  sample: enforce=restricted audit=restricted warn=restricted
PASS  kyverno: enforce=restricted audit=restricted warn=restricted
PASS  default: enforce=baseline audit=restricted warn=restricted
PASS  kube-public: enforce=restricted audit=restricted warn=-
PASS  kube-node-lease: enforce=restricted audit=restricted warn=-
PASS  kube-system: enforce=privileged audit=restricted warn=-
PASS  cilium-secrets: enforce=privileged audit=restricted warn=-
PASS  local-path-storage: enforce=privileged audit=restricted warn=-
PASS  monitoring: enforce=privileged audit=restricted warn=-
PASS  scanners: enforce=privileged audit=restricted warn=-
PASS  a privileged pod is rejected in the restricted namespace sample
PASS  a pod without the restricted settings is rejected in sample
PASS  a hostPath pod is rejected in default (baseline)
PASS  a pod that follows the restricted profile is accepted in sample
== Kyverno policies (P2-U7)
PASS  a privileged pod is refused by disallow-privileged-containers
PASS  a pod without limits is refused by require-resource-limits
PASS  an image from evil.example.com is refused by restrict-image-registries
PASS  an image from ghcr.io (not on the list) is refused by restrict-image-registries
PASS  a Deployment with a privileged container is refused when it is created (autogen)
PASS  a pod with limits, no privilege and an allowed registry is accepted
PASS  an image name without a registry (docker.io) is accepted
PASS  an image from quay.io is accepted
PASS  the system namespace monitoring is outside the policies (documented exclusion)
```

## Findings that remain

- The Prometheus operator reads Secrets in all namespaces (accepted above).
- Grafana reads Secrets in the `monitoring` namespace, because of the chart's Role.
- Several system components hold wildcard or Secret rights; they are built in or come from charts.
- The audit cannot see rights that come from aggregated ClusterRoles added later, or rights granted to `system:authenticated`.
- kubescape C-0015 (list Kubernetes secrets) and C-0185 / C-0187 (cluster-admin use, wildcards) are expected to stay failed for the built-in roles and the two kubeadm groups; the re-scan result is in the P2-U4 and U7 report.

## Acceptance

| Check (P2-U3: "Audit report, no wildcard roles outside system") | Result |
|---|---|
| An audit report exists and is reproducible | Pass: `make rbac-audit`, outputs above |
| No wildcard role exists outside the built-in roles (`system:*`, `kubeadm:*` and the roles labelled `kubernetes.io/bootstrapping=rbac-defaults`, which include `cluster-admin`) | Pass: "Roles with a wildcard that are not built in: none", and the test |
| Least-privilege trims applied and tested | Pass: Grafana, kube-state-metrics, default service accounts |
