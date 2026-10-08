.DEFAULT_GOAL := help
.PHONY: help net-up net-down net-test

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
