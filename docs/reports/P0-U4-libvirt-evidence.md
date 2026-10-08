# P0-U4 evidence: virt-host-validate

Run by the user on the lab host (Ubuntu 24.04, AMD Ryzen 7 8840HS) after installing libvirt and QEMU.

```
virt-host-validate qemu
  hardware virtualization ............ PASS
  /dev/kvm exists / accessible ....... PASS
  /dev/cpu/0/msr, /dev/vhost-net, /dev/net/tun ... PASS
  cgroup cpu, cpuacct, cpuset, memory, blkio ..... PASS
  cgroup devices ..................... WARN (cgroup v2 quirk, not needed)
  IOMMU support / enabled ............ PASS
  secure guest support ............... WARN (confidential computing, not used)
kvm-ok  -> KVM acceleration can be used
virsh -c qemu:///system list --all  -> empty table, no error (checked via group libvirt)
```

Result: no FAIL lines, so the acceptance check passes.
