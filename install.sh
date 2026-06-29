#!/usr/bin/env bash

[ "$EUID" -ne 0 ] && exec sudo "$0" "$@"

cp vpn /usr/local/bin/vpn
chmod +x /usr/local/bin/vpn

mkdir -p /etc/nftables.d/
cp killswitch.nft /etc/nftables.d/killswitch.nft

cp vpn-control /etc/sudoers.d/vpn-control
chmod 440 /etc/sudoers.d/vpn-control

echo "make sure /etc/nftables.conf includes:"
echo "  include \"/etc/nftables.d/*.nft\""
echo ""
echo "then: vpn up"
