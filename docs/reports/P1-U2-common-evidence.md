# P1-U2 evidence: Ansible role `common`

Date: 2026-10-10. Branch: `feat/p1-nodes`. Tool: `ansible-core 2.21.5` in the project virtual environment `.venv` (pinned in `infra/ansible/requirements.txt`).

Nodes: `kg-control-1`, `kg-worker-1`, `kg-worker-2`, reached over SSH with the lab key on `kg-isolated-network` (`ansible -m ping cluster`: all three answer `pong`).

## First run (`ansible-playbook site.yml`)

```
kg-control-1 : ok=11  changed=5  unreachable=0  failed=0  skipped=1
kg-worker-1  : ok=11  changed=5  unreachable=0  failed=0  skipped=1
kg-worker-2  : ok=11  changed=5  unreachable=0  failed=0  skipped=1
```

Changes per node: swap off (and the swap line in `/etc/fstab` commented), kernel modules loaded and listed in `/etc/modules-load.d/kubernetes.conf`, `/etc/sysctl.d/99-kubernetes.conf` written and applied, the cluster block in `/etc/hosts`. The role ends with checks (swap empty, both modules loaded, three sysctl values equal to 1); they pass.

## Idempotence (`make ansible-test` (named `ansible-common-test` when this unit was done)): acceptance check

```
second run:
kg-control-1 : ok=9  changed=0  unreachable=0  failed=0  skipped=2
kg-worker-1  : ok=9  changed=0  unreachable=0  failed=0  skipped=2
kg-worker-2  : ok=9  changed=0  unreachable=0  failed=0  skipped=2
PASS  the second run reports no changes
```

## Direct check and reboot test on `kg-worker-2` (without Ansible)

```
before reboot: swap [] / modules br_netfilter, overlay / sysctl 1 1 1 / hosts marker lines 2 / names resolve
after reboot : swap [] / modules br_netfilter, overlay / sysctl 1 1 1 / hosts marker lines 2 / names resolve
```

## Defect found and fixed

The first reboot test showed the `/etc/hosts` block gone after the restart (marker lines 2 before, 0 after). Cause: `manage_etc_hosts: true` in the node cloud-init seed makes cloud-init rewrite `/etc/hosts` on every boot. The line was removed from `infra/cloud-init/node-user-data.tpl`, the nodes were rebuilt from the template (`make vms-destroy`, `make vms`; 21 checks pass) and the whole sequence above was repeated. The results above are from that second round.

Note: the U1 snapshots belonged to the nodes that were rebuilt, so they no longer exist. Reset snapshots are decided in P1-U11.

Result: the acceptance check of P1-U2 (an idempotent re-run reports no changes) passes, and the settings survive a reboot.
