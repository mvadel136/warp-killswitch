# warp-killswitch

CLI tool to control Cloudflare WARP (via wgcf) with an nftables kill switch.

The kill switch blocks all outgoing traffic if the tunnel goes down, so you don't leak your real IP. Works alongside Tailscale.

## What's inside

```
vpn              the control script
killswitch.nft   nftables kill switch rules
vpn-control      sudoers reference (passwordless sudo for vpn)
install.sh       installs everything and wires up boot persistence
```

## Requirements

- [wgcf](https://github.com/ViRb3/wgcf) configured and generating `/etc/wireguard/wgcf.conf`
- `nftables` and `wireguard-tools` installed
- your user in the `wheel` group (Arch) or `sudo` group (Debian/Ubuntu). `install.sh` detects which one you have.
- Tailscale is optional, the rules handle both cases

## Install

```bash
git clone https://github.com/mvadel136/warp-killswitch
cd warp-killswitch
sudo bash install.sh
```

`install.sh` does the following: copies `vpn` to `/usr/local/bin`, copies `killswitch.nft` to `/etc/nftables.d/`, writes a sudoers rule for your admin group, adds an include line to `/etc/nftables.conf` if it's missing, and enables `nftables.service` and `wg-quick@wgcf.service` so both start on boot.

## Usage

```
vpn up       load kill switch, start tunnel
vpn down     stop tunnel, remove kill switch
vpn restart  restart tunnel without dropping kill switch
vpn status   show tunnel + kill switch state and public IP
```

## How it works

`vpn up` loads `/etc/nftables.d/killswitch.nft` directly. This file does not depend on `/etc/nftables.conf`. It checks that the kill switch table exists before starting the tunnel. If loading the rules fails, or the tunnel fails to start, `vpn up` prints the error and exits without claiming success.

The rules block all outgoing traffic by default, for both IPv4 and IPv6. The only traffic allowed out is: loopback, traffic through the `wgcf` interface, the WireGuard and Tailscale packets that carry the tunnels themselves (matched by fwmark), DHCP, and IPv6 neighbor discovery. IPv6 has no ARP, so without that last rule, IPv6 stops working once the neighbor cache expires.

DNS and LAN traffic are not exempted on purpose. There is no rule for port 53 or your local subnet. If the tunnel is down, DNS lookups fail instead of leaking to your ISP. Other devices on your LAN are also unreachable while the kill switch is active. This is intentional.

`/etc/nftables.conf` is only used for boot persistence. `nftables.service` reads it at boot, before you run `vpn up` yourself. `vpn up` does not read or write this file.

If you also run ufw, firewalld, or another tool that adds its own rules to the `output` hook: in nftables, a `drop` verdict always ends packet processing immediately, but `accept` does not. A more permissive rule in another tool cannot bypass this kill switch. A more restrictive rule in another tool can block tunnel traffic before this ruleset runs, which just means no internet, not a leak.

`vpn restart` only restarts the WireGuard interface. The kill switch stays loaded the whole time.

The Tailscale rules use `oifname` instead of `oif` so nftables loads cleanly even when the `tailscale0` interface doesn't exist yet.

## Note on privacy

WARP routes your traffic through Cloudflare. Cloudflare sees your traffic. This hides you from your ISP and public networks, not from Cloudflare. If you need actual privacy, use Mullvad or ProtonVPN.
