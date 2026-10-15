.DEFAULT_GOAL := help

# The project's own kubeconfig. Every cluster command uses it explicitly, never another one.
PROJECT_KUBECONFIG := $(HOME)/.kube/kubeguard.kubeconfig
# Pinned versions (one place: infra/versions.env). Values are stripped of trailing spaces.
-include infra/versions.env
CILIUM_VERSION := $(strip $(CILIUM))
GATEWAY_API_VERSION := $(strip $(GATEWAY_API))
LOCAL_PATH_VERSION := $(strip $(LOCAL_PATH))
KUBE_PROMETHEUS_STACK_VERSION := $(strip $(KUBE_PROMETHEUS_STACK))
.PHONY: help isolated-network-up isolated-network-down isolated-network-test internet-network-up internet-network-down template-vm-create template-vm-snapshot template-vm-restore-test template-vm-destroy vms vms-status vms-test vms-isolate vms-attach-internet vms-snapshot vms-restore vms-destroy ansible-setup ansible-inventory ansible-apply ansible-test kubectl cilium-install cilium-status cilium-uninstall hubble-ui gateway-api-crds cilium-restart cilium-lb storage-install net-test-u6 sample-app-install sample-app-remove net-test-u8 vms-resize monitoring-secret monitoring-install monitoring-status monitoring-uninstall grafana-password grafana-ui net-test-u7 etcd-snapshot etcd-restore drill-etcd drill-node-drain drill-node-fail drill-node-rejoin up down reset cluster rebuild kubescape-install scan scan-summary scan-compare test-hardening audit-log-size

help: ## List targets
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-28s %s\n", $$1, $$2}'

# Lab lifecycle (P1-U11, P1-U13): up, down, reset, cluster, rebuild (see the targets at the end of this file).
# Naming rules: docs/naming.md

# P0-U5: isolated network (no internet, the only network attacks may use)
isolated-network-up: ## Define and start kg-isolated-network
	virsh -c qemu:///system net-define infra/libvirt/kg-isolated-network.xml
	virsh -c qemu:///system net-autostart kg-isolated-network
	virsh -c qemu:///system net-start kg-isolated-network

isolated-network-down: ## Stop and remove kg-isolated-network
	-virsh -c qemu:///system net-destroy kg-isolated-network
	-virsh -c qemu:///system net-undefine kg-isolated-network

isolated-network-test: ## Run the isolation checks (static; pass VM args via ARGS)
	infra/libvirt/test-isolation.sh $(ARGS)

# P0-U6: template VM. kg-internet-access-network gives internet during builds only (ADR-001)
internet-network-up: ## Define and start kg-internet-access-network (build time only)
	-virsh -c qemu:///system net-define infra/libvirt/kg-internet-access-network.xml
	virsh -c qemu:///system net-start kg-internet-access-network

internet-network-down: ## Stop and remove kg-internet-access-network
	-virsh -c qemu:///system net-destroy kg-internet-access-network
	-virsh -c qemu:///system net-undefine kg-internet-access-network

template-vm-create: ## Create and boot kg-template-vm (provisions, then powers off)
	infra/libvirt/build-template-vm.sh create

template-vm-snapshot: ## Snapshot kg-template-vm as kg-template-clean-snapshot (VM must be shut off)
	infra/libvirt/build-template-vm.sh snapshot

template-vm-restore-test: ## Revert to kg-template-clean-snapshot and check the restore
	infra/libvirt/build-template-vm.sh restore-test

template-vm-destroy: ## Remove kg-template-vm, its disk and seed image
	infra/libvirt/build-template-vm.sh destroy

# P1-U1: cluster node VMs (kg-control-1-vm, kg-worker-1-vm, kg-worker-2-vm)
vms: ## Create the three cluster node VMs from kg-template-vm
	infra/libvirt/build-nodes.sh create

vms-status: ## Show state, address and interfaces of the node VMs
	infra/libvirt/build-nodes.sh status

vms-test: ## Check the node VMs (reachable, sizing, BTF, unique machine-id)
	infra/libvirt/build-nodes.sh test

vms-isolate: ## Detach the internet interface and run the isolation checks
	infra/libvirt/build-nodes.sh isolate

vms-attach-internet: ## Give every node VM its internet interface back (build window)
	infra/libvirt/build-nodes.sh attach

vms-resize: ## Apply the memory sizes in nodes.conf to the existing node VMs (restarts one node at a time)
	infra/libvirt/build-nodes.sh resize

vms-snapshot: ## Snapshot each node VM as <name>-clean-snapshot (SNAP=<label> for another restore point)
	SNAP=$(or $(SNAP),clean) infra/libvirt/build-nodes.sh snapshot

vms-restore: ## Return every node VM to its clean snapshot, or to SNAP=<label> (re-attaches the internet interface)
	SNAP=$(or $(SNAP),clean) infra/libvirt/build-nodes.sh restore

vms-destroy: ## Remove the node VMs, their disks and seeds
	infra/libvirt/build-nodes.sh destroy

# P1-U2: node preparation with Ansible (installed in the project virtual environment .venv)
ansible-setup: ## Create .venv and install the pinned Ansible
	python3 -m venv .venv
	.venv/bin/pip install --quiet -r infra/ansible/requirements.txt

ansible-inventory: ## Generate the Ansible inventory from infra/libvirt/nodes.conf
	infra/ansible/gen-inventory.sh

ansible-apply: ansible-inventory ## Apply all node roles to all nodes; extra options via ANSIBLE_ARGS, for example ANSIBLE_ARGS="-e hardening_audit_enabled=false"
	cd infra/ansible && ../../.venv/bin/ansible-playbook site.yml $(ANSIBLE_ARGS)

ansible-test: ## Run the playbook twice; the second run must change nothing
	infra/ansible/test-idempotence.sh

# P1-U4: talk to the cluster with the project's own kubeconfig only (never another one)
kubectl: ## Run kubectl against the KubeGuard cluster, for example: make kubectl ARGS="get nodes"
	env -u KUBECONFIG kubectl --kubeconfig $(PROJECT_KUBECONFIG) $(ARGS)

# P1-U5: pod network (Cilium) and Hubble. Chart pinned in infra/versions.env, settings in k8s/cilium/values.yaml
cilium-install: ## Install or upgrade Cilium (pinned chart) and wait until it is ready
	env -u KUBECONFIG helm --kubeconfig $(PROJECT_KUBECONFIG) upgrade --install cilium cilium/cilium --version $(CILIUM_VERSION) --namespace kube-system --values k8s/cilium/values.yaml --wait --timeout 10m

cilium-status: ## Show the Cilium status (waits for readiness)
	env -u KUBECONFIG cilium status --kubeconfig $(PROJECT_KUBECONFIG) --wait

cilium-uninstall: ## Remove Cilium (the nodes go back to NotReady)
	env -u KUBECONFIG helm --kubeconfig $(PROJECT_KUBECONFIG) uninstall cilium --namespace kube-system

hubble-ui: ## Open the Hubble UI through a local port-forward (Ctrl+C to stop)
	env -u KUBECONFIG cilium hubble ui --kubeconfig $(PROJECT_KUBECONFIG)

# P1-U6: load balancer (Cilium LB IPAM + L2), Gateway API and storage. Order: crds, cilium-install, cilium-lb, storage.
# Image pulls need the internet: run "make vms-attach-internet" first, and isolate again afterwards.
KUBECTL_P := env -u KUBECONFIG kubectl --kubeconfig $(PROJECT_KUBECONFIG)
gateway-api-crds: ## Install the Gateway API CRDs (standard channel, pinned)
	$(KUBECTL_P) apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v$(GATEWAY_API_VERSION)/standard-install.yaml

cilium-restart: ## Restart the operator and agents so they read a changed ConfigMap (Helm does not do this)
	$(KUBECTL_P) -n kube-system rollout restart deployment/cilium-operator daemonset/cilium daemonset/cilium-envoy
	$(KUBECTL_P) -n kube-system rollout status deployment/cilium-operator --timeout=300s
	$(KUBECTL_P) -n kube-system rollout status daemonset/cilium --timeout=300s
	$(KUBECTL_P) -n kube-system rollout status daemonset/cilium-envoy --timeout=300s

cilium-lb: ## Apply the LoadBalancer address pool and the L2 announcement policy
	$(KUBECTL_P) apply -f k8s/cilium/lb-pool.yaml -f k8s/cilium/l2-policy.yaml

storage-install: ## Install local-path-provisioner (pinned) and make it the default StorageClass
	$(KUBECTL_P) apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v$(LOCAL_PATH_VERSION)/deploy/local-path-storage.yaml
	$(KUBECTL_P) patch storageclass local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

net-test-u6: ## P1-U6 acceptance: LoadBalancer address, Gateway route, PVC bind
	$(KUBECTL_P) apply -f k8s/tests/lb-test.yaml -f k8s/tests/gateway-test.yaml -f k8s/tests/pvc-test.yaml
	$(KUBECTL_P) rollout status deployment/lb-test --timeout=120s
	$(KUBECTL_P) wait --for=condition=Ready pod/pvc-test --timeout=120s
	$(KUBECTL_P) get svc,gateway,httproute,pvc

# P1-U8: sample application (two tiers behind a Gateway). Image pulls need the internet window.
sample-app-install: ## Deploy the sample app and wait until it is ready
	$(KUBECTL_P) apply -f k8s/sample-app/namespace.yaml
	$(KUBECTL_P) apply -f k8s/sample-app/
	$(KUBECTL_P) -n sample rollout status deployment/backend deployment/frontend --timeout=180s

sample-app-remove: ## Remove the sample app (deletes the namespace)
	$(KUBECTL_P) delete namespace sample --ignore-not-found

net-test-u8: ## P1-U8 acceptance: request from the host through the Gateway, Hubble flows
	PROJECT_KUBECONFIG=$(PROJECT_KUBECONFIG) k8s/sample-app/test.sh

# P1-U7: monitoring (Prometheus, Grafana, node and kube-state metrics). Chart pinned in infra/versions.env.
# Image pulls need the internet window. Order: monitoring-secret, monitoring-install.
monitoring-secret: ## Create the Grafana admin Secret with a random password (kept out of git; skipped if it exists)
	$(KUBECTL_P) create namespace monitoring --dry-run=client -o yaml | $(KUBECTL_P) apply -f -
	@$(KUBECTL_P) -n monitoring get secret grafana-admin >/dev/null 2>&1 && echo "grafana-admin already exists" || \
		$(KUBECTL_P) -n monitoring create secret generic grafana-admin --from-literal=admin-user=admin --from-literal=admin-password="$$(openssl rand -base64 18)"

monitoring-install: ## Install or upgrade kube-prometheus-stack (pinned chart) and wait until it is ready
	env -u KUBECONFIG helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update >/dev/null
	env -u KUBECONFIG helm --kubeconfig $(PROJECT_KUBECONFIG) upgrade --install monitoring prometheus-community/kube-prometheus-stack --version $(KUBE_PROMETHEUS_STACK_VERSION) --namespace monitoring --create-namespace --values k8s/monitoring/values.yaml --wait --timeout 10m

monitoring-status: ## Show the monitoring pods, volumes and release
	$(KUBECTL_P) -n monitoring get pods,pvc
	env -u KUBECONFIG helm --kubeconfig $(PROJECT_KUBECONFIG) -n monitoring list

monitoring-uninstall: ## Remove the monitoring release (the namespace, Secret and volumes stay)
	env -u KUBECONFIG helm --kubeconfig $(PROJECT_KUBECONFIG) uninstall monitoring --namespace monitoring

grafana-password: ## Print the Grafana admin password (user: admin)
	@$(KUBECTL_P) -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d; echo

grafana-ui: ## Port-forward Grafana to http://localhost:3000 (Ctrl+C to stop)
	$(KUBECTL_P) -n monitoring port-forward svc/monitoring-grafana 3000:80

net-test-u7: ## P1-U7 acceptance: targets scraped, Grafana healthy, dashboards loaded
	PROJECT_KUBECONFIG=$(PROJECT_KUBECONFIG) k8s/monitoring/test.sh

# P1-U9: etcd snapshot and restore (docs/runbooks/etcd-restore.md). Snapshots go to ~/.local/share/kubeguard/etcd-backups, outside git.
etcd-snapshot: ## Take an etcd snapshot and copy it to the host (outside the repo)
	PROJECT_KUBECONFIG=$(PROJECT_KUBECONFIG) infra/drills/etcd.sh snapshot

etcd-restore: ## Restore etcd from a snapshot: make etcd-restore SNAPSHOT=<file>  (stops the API briefly)
	@test -n "$(SNAPSHOT)" || { echo "usage: make etcd-restore SNAPSHOT=<file>"; exit 2; }
	PROJECT_KUBECONFIG=$(PROJECT_KUBECONFIG) infra/drills/etcd.sh restore $(SNAPSHOT)

drill-etcd: ## P1-U9 drill: snapshot, change state, restore, verify (run make vms-snapshot first)
	PROJECT_KUBECONFIG=$(PROJECT_KUBECONFIG) infra/drills/etcd.sh drill

# P1-U10: node drills on a worker (docs/runbooks/node-failure.md). NODE defaults to kg-worker-1.
NODE ?= kg-worker-1
drill-node-drain: ## P1-U10: drain and uncordon a worker: make drill-node-drain NODE=kg-worker-2
	PROJECT_KUBECONFIG=$(PROJECT_KUBECONFIG) infra/drills/node.sh drain $(NODE)

drill-node-fail: ## P1-U10: power a worker off like a crash, watch recovery, power it on (about 10 min)
	PROJECT_KUBECONFIG=$(PROJECT_KUBECONFIG) infra/drills/node.sh fail $(NODE)

drill-node-rejoin: ## P1-U10: remove a worker, reset it and join it again with a new token
	PROJECT_KUBECONFIG=$(PROJECT_KUBECONFIG) infra/drills/node.sh rejoin $(NODE)

# P1-U11 / P1-U13: lab lifecycle in one command, with timed stages (infra/cluster.sh, docs/runbooks/rebuild.md).
up: ## Start the networks and node VMs, wait until the API answers and all nodes are Ready
	infra/cluster.sh up

down: ## Shut the node VMs down gracefully (frees their RAM)
	infra/cluster.sh down

reset: ## DESTROY the node VMs and create fresh ones (CONFIRM=yes required)
	CONFIRM=$(CONFIRM) infra/cluster.sh reset

cluster: ## From clean VMs to the full cluster (Kubernetes, Cilium, load balancer, Gateway, storage, monitoring, sample app, checks)
	infra/cluster.sh cluster

rebuild: ## reset + cluster with total time against the 40 minute target (CONFIRM=yes required)
	CONFIRM=$(CONFIRM) infra/cluster.sh rebuild

# P2-U1: security scanners (infra/scans/). Raw output goes to ~/.local/share/kubeguard/scans, outside git.
# kube-bench needs its image on the nodes: run "make vms-attach-internet" first while the build window is open.
kubescape-install: ## Install the pinned kubescape CLI into ~/.local/bin (checksum verified)
	infra/scans/install-kubescape.sh

scan: ## Run kube-bench and kubescape, read-only: make scan LABEL=baseline [WHAT=all|kube-bench|kubescape]
	@test -n "$(LABEL)" || { echo "usage: make scan LABEL=<name> [WHAT=all|kube-bench|kubescape]"; exit 2; }
	PROJECT_KUBECONFIG=$(PROJECT_KUBECONFIG) infra/scans/run.sh $(LABEL) $(or $(WHAT),all)

scan-summary: ## Print the scores of a saved scan as markdown: make scan-summary [DIR=<scan dir>] (default: the latest)
	infra/scans/summarize.py $(DIR)

scan-compare: ## Show what changed between two saved scans: make scan-compare BEFORE=<dir> AFTER=<dir>
	@test -n "$(BEFORE)" -a -n "$(AFTER)" || { echo "usage: make scan-compare BEFORE=<scan dir> AFTER=<scan dir>"; exit 2; }
	infra/scans/summarize.py --compare $(BEFORE) $(AFTER)

# P2-U2 / P2-U6: tests of the hardening controls (infra/hardening/test.sh). P2-U10 makes this the one command for all controls.
test-hardening: ## Run the hardening tests, all or one: make test-hardening [CONTROL=anonymous|external-ips|profiling|files|kubelet-tls|tls|pid-limit|seccomp|etcd-encryption|audit]
	PROJECT_KUBECONFIG=$(PROJECT_KUBECONFIG) infra/hardening/test.sh $(or $(CONTROL),all)

audit-log-size: ## Show the size and files of the API audit log on the control-plane node
	@ssh -n -i $(HOME)/.ssh/kubeguard-lab -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR ubuntu@10.77.0.10 'sudo du -sh /var/log/kubernetes/audit; sudo ls -la /var/log/kubernetes/audit; df -h /var/log | tail -1'
