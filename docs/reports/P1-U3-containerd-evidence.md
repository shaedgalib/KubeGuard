# P1-U3 evidence: Ansible role `containerd`

> Note: `crictl` was later changed from 1.37.0 to 1.36.0 when the cluster moved to Kubernetes 1.36.5 (see the P1 spec amendments); the procedure and checks are unchanged.
Date: 2026-10-09. Branch: `feat/p1-nodes`. Pins ([infra/versions.env](../../infra/versions.env)), each checked on the project's release page: containerd 2.3.6 (LTS line, supported until April 2028, supports Kubernetes 1.36 and 1.37), runc 1.5.2 (the version containerd 2.3 expects), cri-tools 1.37.0. Each download is verified against a SHA256 hash pinned in `infra/ansible/group_vars/all.yml`, taken from the project's own checksum files. Ubuntu's packaged containerd (2.2.1) was not used: Kubernetes 1.37 needs containerd 2.3.0 or newer, and the 2.2 line ends on 2026-11-06.

## Runs

```
first run                  : kg-control-1 failed one check (see "Defects"); the other nodes passed
run after the check fix    : changed=0 failed=0 on all three nodes (software and unit already in place)
config version fix         : changed=2 on each node (config file and service restart)
make ansible-test          : second run changed=0 failed=0 on all three nodes
PASS  the second run reports no changes
```

## Direct checks on each node (without Ansible)

```
containerd: active and enabled; containerd v2.3.6; runc 1.5.2; crictl v1.37.0
crictl info: RuntimeReady true        NetworkReady false (expected: Cilium comes in P1-U5)
SystemdCgroup = true (one match in `containerd config dump`)
sandbox image: registry.k8s.io/pause:3.10.2 (containerd default)
/opt/cni/bin: empty (no CNI plugins installed)
`containerd config dump` shows no "migrated" warning after the config was set to version 4
```

## Image pull and reboot

```
kg-worker-1: crictl rmi registry.k8s.io/pause:3.10.2 -> 0 images; crictl pull -> image back (321 kB)
kg-control-1: reboot -> containerd active, RuntimeReady true
```

## Defects found and fixed

- A version check used `head` and `grep -q` under `pipefail`; on one node the program received SIGPIPE (exit 141) although the version was right. The checks now capture each output first. This is the same class of bug as the earlier network check in the template script.
- The configuration was written as `version = 3`; containerd 2.3 uses version 4 and printed a "migrated" warning. The template now says `version = 4`; the plugin paths are unchanged.

Result: the acceptance check of P1-U3 (`crictl info` OK on all nodes) passes, and the role is idempotent.
