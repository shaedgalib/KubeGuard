#cloud-config
# Template for cluster nodes (infra/libvirt/build-nodes.sh). @NAME@ and @SSH_PUBKEY@ are
# replaced when the seed is built; the rendered file is not stored in git.
hostname: @NAME@
# /etc/hosts is not managed by cloud-init: it would be rewritten on every boot and drop the
# cluster block that the Ansible role writes.
users:
  - name: ubuntu
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: true
    ssh_authorized_keys:
      - @SSH_PUBKEY@
# Every clone of the template carries the template's machine-id. Kubernetes nodes need
# unique ones, so each node generates its own on first boot.
bootcmd:
  - [cloud-init-per, once, new-machine-id, sh, -c, "rm -f /etc/machine-id /var/lib/dbus/machine-id && systemd-machine-id-setup && ln -sf /etc/machine-id /var/lib/dbus/machine-id"]
package_update: false
package_upgrade: false
