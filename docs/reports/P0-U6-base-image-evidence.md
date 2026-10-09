# P0-U6 evidence: base VM image and snapshot

Date: 2026-10-09. Branch: `feat/p0-u6`. Host: lab host, libvirt `qemu:///system`.

Image: Ubuntu 24.04 (noble) cloud image, SHA256 verified against the published `SHA256SUMS` (`sha256sum -c`: OK). Stored in pool `kg-images` as `noble-base.img`.

Base VM: `kg-base`, 1 vCPU, 1 GiB RAM, 10 GiB thin qcow2 disk backed by `noble-base.img`, interface on `kg-build` (NAT).

```
make build-net-up      -> Network kg-build defined and started
make base-vm           -> VM created, cloud-init provisioning ran, VM powered off after about 90 s
make base-snapshot     -> Domain snapshot base-clean created (state: shutoff)
make base-restore-test
  PASS  marker written after boot
  Domain snapshot base-clean reverted
  PASS  marker gone after revert (snapshot base-clean restores)
```

The restore test logs in over SSH with the lab key, so it also confirms that the cloud-init user and key are in place.

Result: the base image boots and the snapshot restores. Acceptance check passes.

Defect found and fixed during the run: the existence check for `kg-build` in `build-base-vm.sh` failed under `pipefail` because `grep -q` closed the pipe early. The output is now captured before it is searched.
