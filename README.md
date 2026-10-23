# warp-killswitch

CLI tool to control Cloudflare WARP (via wgcf) with an nftables kill switch.

The kill switch blocks all outgoing traffic if the tunnel goes down, so you don't leak your real IP. Works alongside Tailscale.

## What's inside

```
vpn                     the control script
killswitch.nft          nftables kill switch rules
vpn-control             sudoers reference (passwordless sudo for vpn)
vpn-killswitch.service  loads the kill switch at boot
vpn-resume.service      restarts the tunnel after suspend
wgcf-killswitch.conf    starts the tunnel after the kill switch
install.sh              installs everything and wires up boot persistence
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

`install.sh` does the following: copies `vpn` to `/usr/local/bin`, copies `killswitch.nft` to `/etc/nftables.d/`, writes a sudoers rule for your admin group, installs the systemd units, comments out the `/etc/nftables.d/*.nft` include in `/etc/nftables.conf` (with a backup), and enables the units.

Tested in practice on Arch. Debian/Ubuntu support (admin group detection,
a compatibility fix for older nftables) is implemented and researched, not
yet confirmed on real hardware there. If you run it on Debian or Ubuntu,
I'd like to know how it goes.

## Usage

```
vpn up       load kill switch, start tunnel, enable on boot
vpn down     stop tunnel, remove kill switch, disable on boot
vpn restart  restart tunnel without dropping kill switch
vpn status   show tunnel + kill switch state and public IP
```

<img width="702" height="468" alt="p" src="https://github.com/user-attachments/assets/78bccbbd-e19a-455c-8003-c5e3ced95c8a" />


## How it works

`vpn up` loads `/etc/nftables.d/killswitch.nft` directly. This file does not depend on `/etc/nftables.conf`. It checks that the kill switch table exists before starting the tunnel. If loading the rules fails, or the tunnel fails to start, `vpn up` prints the error and exits.

The rules block all outgoing traffic by default, for both IPv4 and IPv6. The only traffic allowed out is: loopback, traffic through the `wgcf` interface, the WireGuard and Tailscale packets that carry the tunnels themselves (matched by fwmark), DHCP, and IPv6 neighbor discovery. IPv6 has no ARP, so without that last rule, IPv6 stops working once the neighbor cache expires.

DNS and LAN traffic are not exempted on purpose. There is no rule for port 53 or your local subnet. If the tunnel is down, DNS lookups fail instead of leaking to your ISP. Other devices on your LAN are also unreachable while the kill switch is active. This is intentional.

At boot the kill switch loads before the network, then the tunnel starts. Boot follows your last `vpn up` or `vpn down`. The kill switch is not loaded from `/etc/nftables.conf`, so `vpn down` can't leave you offline after a reboot.

After suspend, `vpn-resume.service` starts the tunnel if the kill switch is active.

If you also run ufw, firewalld, or another tool that adds its own rules to the `output` hook: in nftables, a `drop` verdict always ends packet processing immediately, but `accept` does not. A more permissive rule in another tool cannot bypass this kill switch. A more restrictive rule in another tool can block tunnel traffic before this ruleset runs, which just means no internet, not a leak.

`vpn restart` only restarts the WireGuard interface. The kill switch stays loaded the whole time.

The Tailscale rules use `oifname` instead of `oif` so nftables loads cleanly even when the `tailscale0` interface doesn't exist yet.

## Note on privacy

WARP routes your traffic through Cloudflare. Cloudflare sees your traffic. This hides you from your ISP and the websites you visit, not from Cloudflare. A VPN provider isn't fundamentally different, it's also a third party that can see your traffic and can be legally compelled to hand over what it has. What actually differs between providers is how much they retain and whether that's been independently audited, not whether it's technically called a VPN. Cloudflare's only published audit covers its 1.1.1.1 DNS resolver, not the WARP tunnel itself.
