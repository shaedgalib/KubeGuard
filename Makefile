.DEFAULT_GOAL := help
.PHONY: help net-up net-down net-test build-net-up build-net-down base-vm base-snapshot base-restore-test base-destroy

help: ## List targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'

# Targets for up, down, reset and cluster are added in Phase 1.

# P0-U5: isolated lab network
net-up: ## Define and start the isolated kg-lab network
	virsh -c qemu:///system net-define infra/libvirt/kg-lab-net.xml
	virsh -c qemu:///system net-autostart kg-lab
	virsh -c qemu:///system net-start kg-lab

net-down: ## Stop and remove the kg-lab network
	-virsh -c qemu:///system net-destroy kg-lab
	-virsh -c qemu:///system net-undefine kg-lab

net-test: ## Run the isolation checks (static; pass VM args via ARGS)
	infra/libvirt/test-isolation.sh $(ARGS)

# P0-U6: base VM image (kg-build is a temporary NAT network, see ADR-001)
build-net-up: ## Define and start the temporary kg-build NAT network
	virsh -c qemu:///system net-define infra/libvirt/kg-build-net.xml
	virsh -c qemu:///system net-start kg-build

build-net-down: ## Stop and remove the kg-build network
	-virsh -c qemu:///system net-destroy kg-build
	-virsh -c qemu:///system net-undefine kg-build

base-vm: ## Create and boot the kg-base VM (provisions, then powers off)
	infra/libvirt/build-base-vm.sh create

base-snapshot: ## Snapshot kg-base as base-clean (VM must be shut off)
	infra/libvirt/build-base-vm.sh snapshot

base-restore-test: ## Revert to base-clean and check the restore
	infra/libvirt/build-base-vm.sh restore-test

base-destroy: ## Remove kg-base, its disk and seed image
	infra/libvirt/build-base-vm.sh destroy
