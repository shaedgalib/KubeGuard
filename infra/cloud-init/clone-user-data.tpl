#cloud-config
# Template for lab clones of kg-template-vm (see infra/libvirt/test-isolation-vms.sh).
# The clone is a new cloud-init instance, so network config is regenerated for
# its new MAC address. No package work and no power-off: kg-isolated-network has no internet.
hostname: @NAME@
manage_etc_hosts: true
users:
  - name: ubuntu
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: true
    ssh_authorized_keys:
      - @SSH_PUBKEY@
package_update: false
package_upgrade: false
