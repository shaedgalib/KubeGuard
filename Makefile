.DEFAULT_GOAL := help
.PHONY: help isolated-network-up isolated-network-down isolated-network-test internet-network-up internet-network-down template-vm-create template-vm-snapshot template-vm-restore-test template-vm-destroy vms vms-status vms-test vms-isolate vms-snapshot vms-destroy

help: ## List targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-28s %s\n", $$1, $$2}'

# Targets for up, down, reset and cluster are added in Phase 1.
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
	virsh -c qemu:///system net-define infra/libvirt/kg-internet-access-network.xml
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

vms-snapshot: ## Snapshot each node VM as <name>-clean-snapshot
	infra/libvirt/build-nodes.sh snapshot

vms-destroy: ## Remove the node VMs, their disks and seeds
	infra/libvirt/build-nodes.sh destroy
