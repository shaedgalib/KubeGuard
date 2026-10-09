version: 2
# Two network interfaces per node, matched by MAC address.
# isolated0: kg-isolated-network, permanent, fixed address from the DHCP reservation.
# internet0: kg-internet-access-network, present only while building. Its default route has
# the lower metric, so traffic leaves through it while it is attached.
# dhcp-identifier: mac makes the DHCP client identity depend on the MAC address and not on
# the machine-id, which the clones share until they generate their own.
ethernets:
  isolated0:
    match:
      macaddress: "@ISOLATED_MAC@"
    set-name: isolated0
    dhcp4: true
    dhcp-identifier: mac
    dhcp4-overrides:
      route-metric: 200
      use-dns: false
  internet0:
    match:
      macaddress: "@INTERNET_MAC@"
    set-name: internet0
    dhcp4: true
    dhcp-identifier: mac
    dhcp4-overrides:
      route-metric: 100
