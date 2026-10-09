#cloud-config
# Template. @SSH_PUBKEY@ is replaced by infra/libvirt/build-base-vm.sh with the
# public key of ~/.ssh/kubeguard-lab. The rendered file is not stored in git.
hostname: kg-base
users:
  - name: ubuntu
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: true
    ssh_authorized_keys:
      - @SSH_PUBKEY@
package_update: true
package_upgrade: true
packages:
  - qemu-guest-agent
  - curl
  - jq
runcmd:
  - systemctl enable --now qemu-guest-agent
power_state:
  mode: poweroff
  message: base provisioning complete
  timeout: 30
