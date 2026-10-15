# Runbook: operate the KubeGuard lab

How to build, inspect, test, stop and rebuild each layer of the lab, bottom to top. Written 2026-10-10 and extended as units are finished. Names follow [docs/naming.md](../naming.md). Decisions behind the layers: [ADR-001](../adr/ADR-001-lab-network-isolation.md) and [docs/specs/P1-cluster.md](../specs/P1-cluster.md).

## Rules

- Attacks and attack tooling run only on `kg-isolated-network`. The internet-access network is for building only, and nodes are detached from it before any attack work (ADR-001).
- Snapshot the VMs before every attack run and every hardening change.
- Use only the project kubeconfig `~/.kube/kubeguard.kubeconfig` (mode 0600, outside the repository), always through `make kubectl ARGS="..."`. It clears `KUBECONFIG` and names the file explicitly, so a stray variable cannot point `kubectl` at another cluster. It gives full administrator access: never copy it into the repository, chat or logs.
- No work AWS credentials, client credentials or other kubeconfigs on this machine for this project.

## The layers

| Layer | Made by | Check |
|---|---|---|
| Host: KVM, libvirt, storage pool | P0-U4, P0-U6 | `virt-host-validate qemu`, `virsh -c qemu:///system pool-list` |
| Networks `kg-isolated-network`, `kg-internet-access-network` | P0-U5, P0-U6 | `make isolated-network-test` |
| Template VM `kg-template-vm` | P0-U6 | `make template-vm-restore-test` |
| Node VMs `kg-control-1-vm`, `kg-worker-1-vm`, `kg-worker-2-vm` | P1-U1 | `make vms-test` |
| Node setup (Ansible: common, containerd, Kubernetes packages) | P1-U2, U3, U4 | `make ansible-test` |
| Kubernetes cluster | P1-U4 | `make kubectl ARGS="get nodes -o wide"` |
| Pod network and Hubble (Cilium) | P1-U5 | `make cilium-status` |

Nodes:

| Node | Isolated address | Role |
|---|---|---|
| `kg-control-1` | 10.77.0.10 | control plane (API `https://10.77.0.10:6443`) |
| `kg-worker-1` | 10.77.0.11 | worker |
| `kg-worker-2` | 10.77.0.12 | worker |

Shortcut for running a command on a node (lab key, no host-key prompts):

```bash
node() { ssh -i ~/.ssh/kubeguard-lab -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@"$@"; }
```

## 1. Host and storage (P0-U4, P0-U6)

```bash
virt-host-validate qemu                         # no FAIL lines (two WARNs are expected)
virsh -c qemu:///system list --all              # VMs
virsh -c qemu:///system pool-list --all         # kg-storage-pool active, autostart yes
virsh -c qemu:///system vol-list kg-storage-pool
```

- Your user must be in the `libvirt` and `kvm` groups; after adding them, log out and in, or run commands inside `newgrp libvirt`.
- `kg-storage-pool` is the folder `/var/lib/libvirt/images/kubeguard`. It holds `noble-base.img` (the Ubuntu 24.04 cloud image, SHA256 verified against the published `SHA256SUMS`), the template disk and seed, and the node disks and seeds. None of it is stored in git.
- The lab SSH key is `~/.ssh/kubeguard-lab` (no passphrase, used only for lab VMs). The public key is injected into every VM at first boot.

## 2. Networks (P0-U5, P0-U6)

| Network | Range | Internet | Bridge |
|---|---|---|---|
| `kg-isolated-network` | 10.77.0.0/24 (DHCP pool .100-.199; nodes have fixed .10-.12) | none | `kg-isolated-br` |
| `kg-internet-access-network` | 10.78.0.0/24 | NAT, build time only | `kg-internet-br` |

```bash
make isolated-network-up        # define, autostart and start kg-isolated-network
make internet-network-up        # define and start kg-internet-access-network (not autostarted)
make isolated-network-test      # static checks; asks for sudo for the masquerade check. Expect 4 PASS
make isolated-network-down      # stop and remove (only when no VM uses it)
make internet-network-down      # stop and remove; first detach nodes: make vms-isolate
virsh -c qemu:///system net-list --all
```

- Isolation holds because the isolated network has no `<forward>` element, so libvirt adds no NAT or routing for it.
- If `isolated-network-test` prints `SKIP` for the masquerade check, `sudo` could not read the firewall rules; run it in a terminal where `sudo` works.

## 3. Template VM (P0-U6)

The clean Ubuntu VM that every node is cloned from. It sits on the internet-access network while it provisions itself with cloud-init (updates, `qemu-guest-agent`, `curl`, `jq`) and then powers off.

```bash
make internet-network-up
make template-vm-create          # about two minutes; the VM powers off when finished
virsh -c qemu:///system domstate kg-template-vm      # wait for: shut off
make template-vm-snapshot        # kg-template-clean-snapshot
make template-vm-restore-test    # boots, writes a marker, reverts, boots, marker must be gone
make template-vm-destroy         # remove the VM, disk and seed
```

The template must be shut off before nodes are created from it.

## 4. Node VMs (P1-U1)

Each node has two interfaces: `isolated0` (permanent, fixed address through a DHCP reservation) and `internet0` (build window only; while attached it carries the default route with the lower metric). Sizing is set in `infra/libvirt/nodes.conf`: 2 vCPU and 20 GiB disk per node; memory 3 GiB for the control plane and 5 GiB for each worker (raised from 2 GiB each in P1-U7). Change a value there and run `make vms-resize` to apply it to the existing VMs (one node at a time, no rebuild). Three nodes use 13 GiB of RAM.

```bash
make vms                    # create the three nodes and wait until they answer on SSH
make vms-status             # state, address and interfaces of each node
make vms-test               # 21 checks: sizing, BTF, unique machine-ids, node-to-node reachability
make vms-isolate            # detach internet0 and run the isolation checks (all PASS expected)
make vms-attach-internet    # give internet0 back (for builds that need the internet)
make vms-snapshot           # shut down, snapshot each node as <name>-clean-snapshot, start again
make vms-restore            # return every node to its clean snapshot (also re-attaches internet0)
make vms-destroy            # remove the nodes, their disks and seeds
```

- A snapshot captures everything on the node, including the Kubernetes cluster state at that moment. `vms-restore` returns the whole cluster to that moment. No snapshots exist until `make vms-snapshot` is run.
- To stop the lab and free the 6 GiB of RAM, and start it again:

```bash
for v in kg-worker-2-vm kg-worker-1-vm kg-control-1-vm; do virsh -c qemu:///system shutdown $v; done
for v in kg-control-1-vm kg-worker-1-vm kg-worker-2-vm; do virsh -c qemu:///system start $v; done
```

The nodes are not set to start with the host. Start them again after a host reboot. The cluster comes back by itself once the nodes are up. While `internet0` is still attached, run `make internet-network-up` first: that network is not autostarted, and libvirt refuses to start a VM whose network is inactive.

## 5. Node setup with Ansible (P1-U2, U3, U4)

Ansible runs from the project virtual environment `.venv` (not in git), pinned to `ansible-core 2.21.5`.

```bash
sudo apt install -y python3-venv     # once, if the package is missing
make ansible-setup                   # creates .venv and installs the pinned Ansible
make ansible-inventory               # inventory from infra/libvirt/nodes.conf
make ansible-apply                   # all roles on all nodes; a finished node is left unchanged
make ansible-test                    # runs the playbook twice; the second run must change nothing
```

| Role | What it does |
|---|---|
| `common` | swap off, kernel modules `overlay` and `br_netfilter`, sysctl settings, node names in `/etc/hosts` |
| `containerd` | containerd 2.3.6, runc 1.5.2 and `crictl` 1.36.0 from the project release pages, checked against pinned SHA256 hashes; systemd cgroup driver |
| `kubernetes_packages` | `kubelet` and `kubeadm` (and `kubectl` on the control node) 1.36.5, held; `--node-ip` set per node |
| `kubeadm_init` | `kubeadm init` on the control node, then the project kubeconfig is fetched to the host |
| `kubeadm_join` | joins each worker with a short-lived token that is not logged |

- Versions and hashes live in `infra/ansible/group_vars/all.yml`, with a summary in `infra/versions.env`. To change one, look up the new version and its checksum on the project's own release page, edit both files, run `make ansible-apply`, then `make ansible-test`.
- If Ansible reports `Ansible requires blocking IO on stdin/stdout/stderr`, run it with its output redirected to a file and with `</dev/null`.
- The first run needs the internet interface (downloads and image pulls). A node that has been isolated must be given `internet0` back first: `make vms-attach-internet`.

## 6. Container runtime (P1-U3)

```bash
node 10.77.0.10 'sudo systemctl is-active containerd; containerd --version; runc --version | head -1; crictl --version'
node 10.77.0.10 'sudo crictl info | jq -r ".status.conditions[] | .type + \"=\" + .status"'
# RuntimeReady=true. NetworkReady=false until a pod network (Cilium, P1-U5) is installed.
node 10.77.0.10 'sudo containerd config dump | grep SystemdCgroup'     # SystemdCgroup = true
node 10.77.0.10 'sudo crictl images'
```

Configuration is `/etc/containerd/config.toml` (config version 4, only the settings that differ from the defaults) and the unit `/etc/systemd/system/containerd.service`. Both are written by the role; edit the role templates, not the files on the nodes.

## 7. Kubernetes cluster (P1-U4)

Inspect the running cluster (read-only; checked by the researcher on 2026-10-10):

```bash
curl -sk https://10.77.0.10:6443/readyz; echo                # ok
make kubectl ARGS="version"                                   # Server Version: v1.36.5
make kubectl ARGS="get nodes -o wide"                         # 3 nodes, INTERNAL-IP 10.77.0.10 / .11 / .12
make kubectl ARGS="-n kube-system get pods"                   # etcd, apiserver, controller-manager, scheduler Running
make kubectl ARGS="-n kube-system get daemonset kube-proxy"   # NotFound: Cilium replaces kube-proxy
node 10.77.0.10 'cat /etc/kubeadm/kubeadm-config.yaml'        # the configuration kubeadm used
node 10.77.0.10 'kubeadm version -o short; apt-mark showhold' # v1.36.5; kubeadm, kubectl, kubelet held
node 10.77.0.11 'cat /etc/default/kubelet'                    # KUBELET_EXTRA_ARGS=--node-ip=10.77.0.11
```

State before the pod network is installed (P1-U5): nodes `NotReady`, CoreDNS `Pending`. This is expected.

Other read-only commands: `make kubectl ARGS="get pods -A -o wide"`, `make kubectl ARGS="describe node kg-worker-1"`, `make kubectl ARGS="get events -A --sort-by=.lastTimestamp"`.

### Rebuild the cluster

The normal way is Ansible: `make ansible-apply`, then `make ansible-test`. To start from clean nodes: `make vms-destroy`, `make vms`, `make ansible-apply`.

### Reset and rebuild by hand (reference; not yet run by hand by the researcher)

This removes only the Kubernetes state; the VMs, containerd and the packages stay. If a step fails, record the exact output and use the reset again.

```bash
# 1. reset each node, and drop the stale kubeconfig
node 10.77.0.10 'sudo kubeadm reset -f'
node 10.77.0.11 'sudo kubeadm reset -f'
node 10.77.0.12 'sudo kubeadm reset -f'
rm ~/.kube/kubeguard.kubeconfig

# 2. initialise the control plane (prints a join command; do not paste it anywhere)
node 10.77.0.10 'sudo kubeadm init --config /etc/kubeadm/kubeadm-config.yaml'

# 3. get the kubeconfig to the host
node 10.77.0.10 'sudo cat /etc/kubernetes/admin.conf' > ~/.kube/kubeguard.kubeconfig
chmod 600 ~/.kube/kubeguard.kubeconfig
make kubectl ARGS="get nodes"                                 # only kg-control-1, NotReady

# 4. create a short-lived join command, then run it on each worker
node 10.77.0.10 'sudo kubeadm token create --ttl 15m --print-join-command'
node 10.77.0.11 'sudo <join command> --node-name kg-worker-1 --cri-socket unix:///run/containerd/containerd.sock'
node 10.77.0.12 'sudo <join command> --node-name kg-worker-2 --cri-socket unix:///run/containerd/containerd.sock'

# 5. check
make kubectl ARGS="get nodes -o wide"                         # three nodes, all NotReady
make ansible-test                                              # PASS: Ansible agrees with the manual result
```

Installing `kubelet` and `kubeadm` by hand, if a node has no packages: add the `pkgs.k8s.io` v1.36 repository, check that the key fingerprint is `DE15B14486CD377B9E876E1A234654DA9A296436`, install `kubelet=1.36.5-1.1` and `kubeadm=1.36.5-1.1` (plus `kubectl=1.36.5-1.1` on the control node), hold them, set `KUBELET_EXTRA_ARGS=--node-ip=<node address>` in `/etc/default/kubelet`, and enable `kubelet`. The role `kubernetes_packages` is the exact reference.

## 8. Pod network and Hubble (P1-U5)

Cilium (chart 1.20.2, settings in `k8s/cilium/values.yaml`) is the pod network and replaces kube-proxy. Hubble shows the flows.

```bash
make cilium-install        # install or upgrade the pinned chart and wait until ready
make cilium-status         # Cilium, Operator, Envoy and Hubble Relay should be OK, 3 of 3 agents
make kubectl ARGS="get nodes"                       # Ready
make kubectl ARGS="-n kube-system get pods -o wide" # cilium x3, cilium-envoy x3, operator, hubble-relay, hubble-ui, coredns
make hubble-ui             # browser view of the flows (Ctrl+C to stop the port-forward)
make cilium-uninstall      # remove Cilium; the nodes return to NotReady
```

Flows on the command line (stop the port-forward afterwards, for example with `kill %1`):

```bash
env -u KUBECONFIG cilium hubble port-forward --kubeconfig ~/.kube/kubeguard.kubeconfig &
hubble observe --server localhost:4245 --namespace <namespace> --last 20
hubble status --server localhost:4245          # Connected Nodes: 3/3
```

A quick test of Services without kube-proxy: create a pod and Service in a test namespace, then fetch it from a client pod that stays alive a few seconds (`sh -c 'wget -qO- -T 5 http://web'`); delete the namespace afterwards.

## 9. LoadBalancer, Gateway API and storage (P1-U6)

Layer 4 and layer 7 entry points and persistent volumes, all built on Cilium and local-path. Design and flows: the P1-U6 entry in `docs/specs/P1-cluster.md`.

Image pulls need the internet window: `make vms-attach-internet` first (the internet network must be up).

Order (CRDs first, restart after every Cilium values change):

```bash
make gateway-api-crds     # Gateway API CRDs, pinned version
make cilium-install       # helm upgrade with k8s/cilium/values.yaml
make cilium-restart       # Helm does not restart Cilium after a ConfigMap change
make cilium-lb            # address pool 10.77.0.200-220 and the L2 announcement policy
make storage-install      # local-path-provisioner, default StorageClass
make net-test-u6          # acceptance check
```

Check from the host (it sits on the isolated bridge):

```bash
make kubectl ARGS="get svc lb-test"
curl -s -o /dev/null -w "%{http_code}\n" http://10.77.0.200      # layer 4, expect 200
make kubectl ARGS="get gateway gw-test"
curl -si http://10.77.0.201 | head -3                            # layer 7, expect 200 and server: envoy
make kubectl ARGS="-n kube-system get lease"                     # cilium-l2announce-* shows who answers ARP
```

Remove the test objects: `make kubectl ARGS="delete -f k8s/tests/"`.

## 10. Sample application (P1-U8)

A two-tier web app behind a Gateway, used to prove the entry path and to see flows in Hubble. Image pulls need the internet window.

```bash
make sample-app-install      # namespace sample: backend, frontend, Gateway, HTTPRoute
make net-test-u8             # requests / and /api from the host, prints Hubble flows
make sample-app-remove       # delete the namespace
```

A `no healthy upstream` answer right after an install means Envoy has not yet learned the endpoints; wait a few seconds and retry (the test already does). Flows can also be read by hand: `make kubectl ARGS="-n kube-system exec ds/cilium -c cilium-agent -- hubble observe --namespace sample --last 20"` (one node only; the test loops over all agents).

## 11. Monitoring (P1-U7)

Prometheus and Grafana (kube-prometheus-stack, chart pinned in `infra/versions.env`) in namespace `monitoring`. Image pulls need the internet window.

```bash
make vms-resize              # once: apply the memory sizes from nodes.conf
make monitoring-secret       # Grafana admin Secret with a random password (not in git)
make monitoring-install      # helm install, waits until ready
make net-test-u7             # targets scraped, Grafana healthy, dashboards loaded
make grafana-password        # print the admin password (user: admin)
make grafana-ui              # http://localhost:3000 through a port-forward, Ctrl+C to stop
make monitoring-uninstall    # remove the release (namespace, Secret and volume stay)
```

The test reaches Prometheus and Grafana through the API server's Service proxy, for example `make kubectl ARGS='get --raw /api/v1/namespaces/monitoring/services/monitoring-grafana:80/proxy/api/health'`.

## 12. etcd snapshot and restore (P1-U9)

Own runbook: [etcd-restore.md](etcd-restore.md). In short: `make etcd-snapshot` saves a snapshot to the host (outside git), `make etcd-restore SNAPSHOT=<file>` restores it, `make drill-etcd` runs the whole drill. Take `make vms-snapshot` first.

## 13. Node drain, failure and rejoin (P1-U10)

Own runbook: [node-failure.md](node-failure.md). In short: `make drill-node-drain NODE=...`, `make drill-node-fail NODE=...` and `make drill-node-rejoin NODE=...` (workers only).

## 14. Lifecycle and rebuild (P1-U11, P1-U13)

Own runbook: [rebuild.md](rebuild.md). In short: `make up`, `make down`, `make reset CONFIRM=yes`, `make cluster` and `make rebuild CONFIRM=yes` (reset plus cluster, timed).

## 15. Baseline hardening (P2-U2, P2-U6)

Own runbook: [hardening.md](hardening.md). In short: the `hardening` role is part of `make ansible-apply`; take `make vms-snapshot SNAP=pre-u2` and `make etcd-snapshot` first, then `make ansible-apply ANSIBLE_ARGS="-e hardening_audit_enabled=false -e hardening_encryption_enabled=false"` (U2) and later `make ansible-apply` (U6). Check with `make test-hardening`, scan with `make scan LABEL=<name>`, compare with `make scan-compare`. Scan output and encryption key copies stay outside the repository (`~/.local/share/kubeguard/`).

## Troubleshooting

| Symptom | Check |
|---|---|
| `Permission denied` on the libvirt socket | Your session lacks the `libvirt` group: log out and in, or use `newgrp libvirt` |
| A node does not answer on SSH | `make vms-status` (running?); `virsh -c qemu:///system net-dhcp-leases kg-isolated-network`; is `kg-isolated-network` active? |
| `make vms` says a node already exists | `make vms-destroy` first |
| `make vms` or `make template-vm-create` says a network is not active | `make isolated-network-up` / `make internet-network-up` |
| Ansible `unreachable` | `make vms-status`, then `node 10.77.0.10 true` |
| Downloads or image pulls fail on a node | The node is isolated: `make vms-attach-internet` |
| `kubeadm init` fails midway | `node 10.77.0.10 'sudo kubeadm reset -f'`, then `make ansible-apply` |
| Rebuild fails on the Kubernetes repository key | The key expired on 2026-12-29: update the fingerprint pin in `infra/ansible/group_vars/all.yml` |
| `kubectl` warns about version skew | The host `kubectl` is more than one minor version away from the server: install a matching client, or use `kubectl` on `kg-control-1` (`node 10.77.0.10 'sudo kubectl --kubeconfig /etc/kubernetes/admin.conf ...'`) |
| Nodes do not start after a host reboot ("network ... is not active") | `internet0` is still attached: `make internet-network-up`, then start the VMs |
| `LoadBalancer` has an address but `curl` says "No route to host", or the GatewayClass stays `Unknown` | Cilium was not restarted after a values change: `make cilium-restart` |

## Known limits

- The Kubernetes apt signing key expires on 2026-12-29.
- The host `kubectl` (1.35.7) is one minor version behind the cluster (1.36.5), which is within the supported skew. Keep it within one minor version of the server.
- Host tools: Helm 4.3.0 (Helm 4.3.x supports Kubernetes 1.34 to 1.37; the old Helm 3.16.3 is kept as `helm-3.16.3`), Cilium CLI 0.20.1, Hubble CLI 1.20.2, all in `~/.local/bin`.
- The masquerade check of the isolation test needs a terminal where `sudo` can ask for a password.
