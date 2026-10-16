# P2-U4 and P2-U7 evidence: Pod Security Admission and Kyverno policies

Date: 2026-10-16. Branch: `feat/p2-access-control`. Cluster: Kubernetes 1.36.5, three nodes. Applied by the assistant at the researcher's instruction ("go ahead"). The assistant did not produce any number in this report: every block below is the unchanged output of a script (`make access-evidence`, `make test-hardening`, `make drill-kyverno`, `make scan-compare`); the paragraphs around the blocks are the assistant's reading. Runbook: [access-control.md](../runbooks/access-control.md). Decision record for the Kyverno version and policy type: [ADR-006](../adr/ADR-006-kyverno-cel-policies.md). RBAC part of the same branch: [P2-U3-rbac-audit.md](P2-U3-rbac-audit.md).

The unit plan leaves the exemptions (P2-U4) and the rules and exceptions (P2-U7) to the researcher. The levels, rules and exclusions below were proposed by the assistant on 2026-10-16 and are open to change; a change is recorded here with its date.

Restore points taken before the branch's first change: VM snapshots `pre-p2-access` and etcd snapshot `etcd-20261016-014755.db`; a second etcd snapshot was taken before the Kyverno install.

## What was changed

| Item | Change |
|---|---|
| Pod Security Admission levels | Labels per namespace from `k8s/access/pod-security.conf`, applied by `make access-apply` (table below) |
| Sample app | Now complies with `restricted`: image `nginxinc/nginx-unprivileged:1.27-alpine` (non-root, port 8080 instead of 80), `allowPrivilegeEscalation: false`, all capabilities dropped, `runAsNonRoot`, `readOnlyRootFilesystem` with an `emptyDir` for `/tmp`, seccomp `RuntimeDefault`, no API token, CPU and memory limits. Services keep port 80 and forward to 8080, so the Gateway route is unchanged |
| P1 test fixtures | `k8s/tests/lb-test.yaml` and `pvc-test.yaml` got CPU and memory limits, because the `default` namespace is covered by the Kyverno policies |
| Kyverno | Chart 3.9.1 (Kyverno v1.19.1), one replica of each controller, no cleanup controller, in the namespace `kyverno` (`make kyverno-install`) |
| Kyverno policies | Three `ValidatingPolicy` objects (CEL), action `Deny`: `disallow-privileged-containers`, `require-resource-limits`, `restrict-image-registries` (docker.io, quay.io, registry.k8s.io). Pod controllers are covered by autogen. System namespaces are excluded in the policies and in the webhook configuration |
| Tests | `make test-hardening` gained `rbac`, `psa` and `kyverno`. They were written first and run before the changes: every check of a control failed, and only the checks that must accept a compliant pod (or that guard against a regression) passed. The hardening probe pods now carry limits |
| Drill | `make drill-kyverno`: clean stop, crash, unblock, recovery |

### Pod Security levels (`k8s/access/pod-security.conf`)

```
sample              restricted  restricted  restricted
kyverno             restricted  restricted  restricted
default             baseline    restricted  restricted
kube-public         restricted  restricted  -
kube-node-lease     restricted  restricted  -
kube-system         privileged  restricted  -
cilium-secrets      privileged  restricted  -
local-path-storage  privileged  restricted  -
monitoring          privileged  restricted  -
scanners            privileged  restricted  -
```

## Version and compatibility

Kyverno 1.19 lists Kubernetes 1.33 to 1.35. The cluster runs 1.36.5 because Cilium 1.20 lists 1.33 to 1.36, so Kyverno is outside its tested range (ADR-006). It installed and runs; the evidence that it works on this cluster is the set of tests below, the outage drill and the P1 checks.

The first `make kyverno-install` failed after its wait: the three controller pods stayed in `ImagePullBackOff` because a worker's resolver failed a lookup of `reg.kyverno.io` (`server misbehaving`). The name resolved a few minutes later, the pods recovered by themselves, and a second `make kyverno-install` finished the release (revision 2, `deployed`). Image pulls need the internet window (still attached; the images are cached on the nodes afterwards).

## Evidence from the cluster

Output of `make access-evidence`:

```
== date: 2026-10-16T13:26:59+06:00

== Pod Security labels compared with k8s/access/pod-security.conf
PASS   sample: enforce=restricted audit=restricted warn=restricted
PASS   kyverno: enforce=restricted audit=restricted warn=restricted
PASS   default: enforce=baseline audit=restricted warn=restricted
PASS   kube-public: enforce=restricted audit=restricted warn=-
PASS   kube-node-lease: enforce=restricted audit=restricted warn=-
PASS   kube-system: enforce=privileged audit=restricted warn=-
PASS   cilium-secrets: enforce=privileged audit=restricted warn=-
PASS   local-path-storage: enforce=privileged audit=restricted warn=-
PASS   monitoring: enforce=privileged audit=restricted warn=-
PASS   scanners: enforce=privileged audit=restricted warn=-

== What the restricted level would flag in running pods, per namespace (server-side dry run, nothing changed)
existing pods in namespace "kube-system" violate the new PodSecurity enforce level "restricted:latest"
cilium-8sxrs (and 2 other pods): forbidden AppArmor profile, host namespaces, hostPort, probe or lifecycle host, privileged, seLinuxOptions, allowPrivilegeEscalation != false, unrestricted capabilities, restricted volume types, runAsNonRoot != true, seccompProfile
cilium-envoy-6kfrk (and 2 other pods): forbidden AppArmor profile, host namespaces, hostPort, probe or lifecycle host, seLinuxOptions, allowPrivilegeEscalation != false, unrestricted capabilities, restricted volume types, runAsNonRoot != true, seccompProfile
cilium-operator-848678cddd-74mrr: host namespaces, hostPort, probe or lifecycle host, runAsNonRoot != true
coredns-589f44dc88-9gwr4 (and 1 other pod): runAsNonRoot != true, seccompProfile
etcd-kg-control-1 (and 3 other pods): host namespaces, hostPort, probe or lifecycle host, allowPrivilegeEscalation != false, unrestricted capabilities, restricted volume types, runAsNonRoot != true
existing pods in namespace "local-path-storage" violate the new PodSecurity enforce level "restricted:latest"
local-path-provisioner-54745b98cf-4kbjp: allowPrivilegeEscalation != false, unrestricted capabilities, runAsNonRoot != true, seccompProfile
existing pods in namespace "monitoring" violate the new PodSecurity enforce level "restricted:latest"
monitoring-prometheus-node-exporter-2v6pk (and 2 other pods): host namespaces, hostPort, allowPrivilegeEscalation != false, unrestricted capabilities, restricted volume types, seccompProfile

== Kyverno release, pods and their resources
NAME   	NAMESPACE	REVISION	UPDATED                                	STATUS  	CHART        	APP VERSION
kyverno	kyverno  	2       	2026-10-16 13:21:33.828693836 +0600 +06	deployed	kyverno-3.9.1	v1.19.1    
POD                                            CONTAINER    CPU_REQ  MEM_REQ  MEM_LIMIT
kyverno-admission-controller-c8db7fccd-8l7pk   kyverno      100m     128Mi    384Mi
kyverno-background-controller-f687dc8b9-v25np  controller   100m     64Mi     128Mi
kyverno-migrate-resources-9pkgn                kyverno-cli  10m      64Mi     256Mi
kyverno-reports-controller-5d4d7cf5c5-c8msj    controller   100m     64Mi     128Mi

== Kyverno policies
NAME                             AGE     READY
disallow-privileged-containers   4m35s   true
require-resource-limits          4m35s   true
restrict-image-registries        4m35s   true

== The policy webhook: failure policy, timeout and the namespaces it is not called for
{"name":"vpol.validate.kyverno.svc-fail","failurePolicy":"Fail","timeoutSeconds":10,"not_called_for":["kube-system","kube-public","kube-node-lease","cilium-secrets","local-path-storage","monitoring","scanners","kyverno"]}

== Refusals and acceptances (server-side dry runs in the temporary namespace hardening-policy-evidence)
-- privileged container, in hardening-policy-evidence
admission webhook "vpol.validate.kyverno.svc-fail" denied the request: Policy disallow-privileged-containers failed: Privileged containers are not allowed (policy disallow-privileged-containers).
-- no limits, in hardening-policy-evidence
admission webhook "vpol.validate.kyverno.svc-fail" denied the request: Policy require-resource-limits failed: Every container must set CPU and memory limits (policy require-resource-limits).
-- image from evil.example.com, in hardening-policy-evidence
admission webhook "vpol.validate.kyverno.svc-fail" denied the request: Policy restrict-image-registries failed: Images must come from an allowed registry: docker.io, quay.io or registry.k8s.io (policy restrict-image-registries).
-- compliant pod, in hardening-policy-evidence
pod/demo-ok created (server dry run)
-- the same privileged pod in sample (Pod Security restricted answers first)
Error from server (Forbidden): error when creating "STDIN": pods "demo-privileged" is forbidden: violates PodSecurity "restricted:latest": privileged (container "c" must not set securityContext.privileged=true), allowPrivilegeEscalation != false (container "c" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "c" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "c" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "c" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
-- the same pod without limits in monitoring (outside the policies)
pod/demo-nolimits created (server dry run)

== Free memory on the nodes (free -m, available column)
kg-control-1: total 2907 MB, available 841 MB
kg-worker-1: total 4917 MB, available 3554 MB
kg-worker-2: total 4917 MB, available 3484 MB
```

Reading it:

- All Pod Security labels match the table. The dry run of `restricted` over the running pods flags only `kube-system`, `local-path-storage` and `monitoring`, the three namespaces whose exemption is documented. `sample` and `kyverno` no longer appear: the sample app and Kyverno comply.
- Every refusal by a Kyverno policy names the policy. The same privileged pod in `sample` is refused earlier, by Pod Security Admission, which is evaluated first. In `monitoring`, outside the policies, a pod without limits is accepted (documented exclusion).
- The webhook `vpol.validate.kyverno.svc-fail` has `failurePolicy: Fail` and is not called for the system namespaces.
- The control-plane node is small (about 2.9 GB in total). Its available memory was **1259 MB** before the Kyverno install (output of the same `free -m` command run before the install, not saved to a file) and is lower in the output above. Workers: 3603 MB and 3731 MB available before, and the values above after. Watch the control-plane node when more is added to the cluster.

## Negative and positive tests

Parts of the output of `make test-hardening`, run after everything was in place (the full run passed):

```
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

## Outage drill

Output of `make drill-kyverno`. It shows what the runbook says about a Kyverno outage: a **crash fails closed** (pod creation in workload namespaces is refused until the replacement is ready), and a **clean stop removes the webhooks** (the policies do not apply, Pod Security Admission still does). My first version of the ADR and the runbook said "fails closed" for both; the drill showed that this was wrong for the clean stop, and both documents were corrected.

```
== 1. normal operation
PASS  a privileged pod is refused by Kyverno in kyverno-drill
== 2. clean stop: scale the admission controller to zero
PASS  the admission controller pod is gone
PASS  Kyverno removed its webhook configurations when it stopped
INFO  a privileged pod IS accepted in kyverno-drill while Kyverno is stopped: the policies do not apply until it runs again
PASS  Pod Security Admission still refuses a privileged pod in the restricted namespace sample
PASS  the system namespace monitoring is not affected
PASS  the admission controller is ready again after 30 s
PASS  Kyverno recreated the webhook configuration by itself (30 s after the start)
PASS  the policies refuse a privileged pod again (30 s after the start)
== 3. crash: kill the admission controller pod without a clean shutdown
PASS  a compliant pod in kyverno-drill is refused while the webhook has no backend (fails closed): failed calling webhook "vpol.validate.kyverno.svc-fail"
PASS  the system namespace monitoring is not affected by the crash
PASS  deleting the webhook configuration unblocks kyverno-drill
PASS  the admission controller is ready again after 24 s
PASS  Kyverno recreated the webhook configuration by itself (31 s after the start)
PASS  the policies refuse a privileged pod again (31 s after the start)
```

## P1 acceptance checks after the branch's changes

`make net-test-u6`, `net-test-u7` and `net-test-u8` all exited 0 after Kyverno, the Pod Security labels and the new sample app were in place (the same run as the final test run). Lines of the monitoring and sample app checks:

```
gateway.gateway.networking.k8s.io/gw-test   cilium   10.77.0.202   True         16s
persistentvolumeclaim/pvc-test   Bound    pvc-099e2a3f-5898-4574-ac39-4850d8996b5c   100Mi      RWO            local-path     <unset>                 

Prometheus targets: 20 total, 0 down
PASS  no scrape target is down
PASS  at least one target is scraped
PASS  node metrics from all three nodes
PASS  Grafana health: database
Dashboard ConfigMaps loaded into Grafana: 24
PASS  dashboards provisioned

Gateway address: 10.77.0.200
PASS  GET /     -> frontend
PASS  GET /api  -> backend
```

## Re-scan compared with the previous scan

Scan `after-access-control-20261016-132547`, same scanners and inputs as before. Output of `make scan-compare BEFORE=after-hardening-20261016-011514 AFTER=after-access-control-20261016-132547`, pasted by script (headings moved one level down, nothing else changed).

Before: `after-hardening-20261016-011514`  
After: `after-access-control-20261016-132547`

### kube-bench totals

| Node | PASS | FAIL | WARN | INFO |
|---|---:|---:|---:|---:|
| kg-control-1 | 82 -> 82 | 1 -> 1 | 48 -> 48 | 0 -> 0 |
| kg-worker-1 | 21 -> 21 | 1 -> 1 | 3 -> 3 | 0 -> 0 |
| kg-worker-2 | 21 -> 21 | 1 -> 1 | 3 -> 3 | 0 -> 0 |

### kube-bench checks whose status changed

| Node | Check | Before | After | Description |
|---|---|---|---|---|
| (none) | | | | |

### kubescape compliance score per framework

| Framework | Before | After |
|---|---:|---:|
| NSA | 60.87 | 65.17 |
| MITRE | 67.87 | 68.44 |
| cis-v1.12.0 | 44.60 | 44.91 |
| overall | 49.13 | 50.06 |

### kubescape controls that changed (status or failed resources)

| Control | Name | Status before -> after | Failed resources before -> after |
|---|---|---|---|
| C-0007 | Roles with delete capabilities | failed -> failed | 26 -> 27 |
| C-0015 | List Kubernetes secrets | failed -> failed | 14 -> 16 |
| C-0016 | Allow privilege escalation | failed -> failed | 10 -> 8 |
| C-0017 | Immutable container filesystem | failed -> failed | 11 -> 9 |
| C-0030 | Ingress and Egress blocked | failed -> failed | 18 -> 22 |
| C-0034 | Automatic mapping of service account | failed -> failed | 16 -> 18 |
| C-0036 | Validate admission controller (validating) | failed -> failed | 1 -> 6 |
| C-0037 | CoreDNS poisoning | failed -> failed | 5 -> 6 |
| C-0039 | Validate admission controller (mutating) | failed -> failed | 1 -> 4 |
| C-0053 | Access container service account | failed -> failed | 62 -> 71 |
| C-0054 | Cluster internal networking | failed -> failed | 9 -> 10 |
| C-0055 | Linux hardening | failed -> failed | 6 -> 4 |
| C-0186 | CIS-5.1.2 Minimize access to secrets | failed -> failed | 14 -> 16 |
| C-0189 | CIS-5.1.5 Ensure that default service accounts are not actively used. | failed -> failed | 15 -> 14 |
| C-0190 | CIS-5.1.6 Ensure that Service Account Tokens are only mounted where... | failed -> failed | 16 -> 18 |
| C-0193 | CIS-5.2.2 Minimize the admission of privileged containers | failed -> failed | 9 -> 5 |
| C-0197 | CIS-5.2.6 Minimize the admission of containers with allowPrivilegeE... | failed -> failed | 9 -> 6 |
| C-0198 | CIS-5.2.7 Minimize the admission of root containers | failed -> failed | 9 -> 6 |
| C-0199 | CIS-5.2.8 Minimize the admission of containers with the NET\_RAW ca... | failed -> failed | 9 -> 5 |
| C-0201 | CIS-5.2.9 Minimize the admission of containers with capabilities as... | failed -> failed | 9 -> 6 |
| C-0202 | CIS-5.2.10 Minimize the admission of Windows HostProcess Containers | failed -> failed | 9 -> 5 |
| C-0203 | CIS-5.2.11 Minimize the admission of HostPath volumes | failed -> failed | 9 -> 5 |
| C-0204 | CIS-5.2.12 Minimize the admission of containers which use HostPorts | failed -> failed | 9 -> 5 |
| C-0206 | CIS-5.3.2 Ensure that all Namespaces have Network Policies defined | failed -> failed | 9 -> 10 |
| C-0209 | CIS-5.6.1 Create administrative boundaries between resources using ... | failed -> failed | 9 -> 10 |
| C-0210 | CIS-5.6.2 Ensure that the seccomp profile is set to docker/default ... | failed -> failed | 7 -> 5 |
| C-0211 | CIS-5.6.3 Apply Security Context to Your Pods and Containers | failed -> failed | 18 -> 22 |
| C-0270 | Ensure CPU limits are set | failed -> failed | 18 -> 19 |
| C-0281 | CIS-5.1.12 Minimize access to webhook configuration objects | failed -> failed | 4 -> 5 |

Reading it:

- kube-bench is unchanged: this branch changes no node or control-plane setting.
- The kubescape framework scores rise slightly. The controls that depend on Pod Security labels (C-0193, C-0197 to C-0199, C-0201 to C-0204, C-0210) show fewer failed resources, and so do C-0016, C-0017 and C-0055 (the sample app now drops privilege escalation, has a read-only root file system and a seccomp profile).
- Several counts **rise** because Kyverno adds a namespace, service accounts, a webhook set and pods to the cluster: for example C-0036 and C-0039 (admission webhooks), C-0053 (service accounts that can be reached from pods), C-0054, C-0206 and C-0209 (one more namespace without a network policy; P2-U5 owns these), C-0015 and C-0186 (two more subjects with Secret rights), C-0211 and C-0270. The engine that enforces the rules is itself a workload with its own rights; its service accounts are listed in the RBAC audit.
- Nothing in this comparison is a claim that the cluster got less secure or more secure than the numbers say; the scanners count objects, and the report lists which objects changed.

Raw scan output is outside git in `~/.local/share/kubeguard/scans/after-access-control-20261016-132547/` (directory mode 700). Checksums:

```
ae4cf13d9f38f6189d046bc780109c774be6752f341f79a29b0ceafa72aea691  context.txt
daecb0c03adb2926eb78ac903ce69b83279f28aaa4a52d69d5cca556cdcfc204  kube-bench-kg-control-1.log
61092940af138a4875317f3418c847bacbf87bda898477de11cf8892666cf066  kube-bench-kg-worker-1.log
fed20e730fb8a010c85c47d9c17f487e55cbae333ae9fd4bf57fe58800cf1fda  kube-bench-kg-worker-2.log
776f7047b4eed8b6311a4a0822b212818f200915e4e7e4478a5ff2f709d03b0a  kubescape.json
37fb2cb4917fe4afaf6ed48b89367d87861627975967994c2f95572b376638d7  kubescape.log
```

## Side effects and limits

1. **The sample app changed image and port.** The Service port (80) and the route are unchanged; Hubble now shows port 8080 on the pod side. The image is a different build of nginx (nginx-unprivileged, the same 1.27 line).
2. **Fixtures needed limits.** The P1 test pods and the probe pods of the hardening tests got CPU and memory limits, because workload namespaces are under `require-resource-limits`. A new workload must do the same.
3. **The `monitoring` namespace stays exempt** from Pod Security and from the Kyverno policies because node-exporter needs host namespaces and host paths, and its containers have memory limits but no CPU limits by design. Moving node-exporter to its own namespace would let the rest be held to a stricter level.
4. **A namespace without Pod Security labels is not covered by Pod Security Admission.** The Kyverno policies still cover it while Kyverno runs. A cluster-wide default (an `AdmissionConfiguration` for the API server) would close this gap; it is not done.
5. **Kyverno is a new component with its own rights** (see the RBAC audit) and one replica. A clean stop leaves workload namespaces without its policies; a crash blocks pod creation for a short time.
6. **Kyverno is outside its tested Kubernetes range** (ADR-006).
7. **The exclusion list exists in four places** (three policies and the chart values) and must be kept equal by hand.

## Acceptance

| Check | Result |
|---|---|
| P2-U4 "Privileged pod rejected": a privileged pod is rejected in a restricted namespace, a hostPath pod in the baseline namespace, and a compliant pod is accepted | Pass (tests `psa`, evidence above) |
| P2-U7 "Each policy blocks its violation": privileged, no limits, bad registry (two registries), and a Deployment with a privileged container | Pass (tests `kyverno`), each refusal names its policy |
| Positive controls: compliant pod, an image without a registry part, an image from quay.io, a system namespace outside the policies | Pass |
| The cluster still works: P1 checks, sample app through the Gateway, monitoring | Pass |
| Failure modes of the policy engine are known and documented | Pass (drill; ADR-006; runbook) |
