# warp-killswitch

CLI tool to control Cloudflare WARP (via wgcf) with an nftables kill switch.

The kill switch blocks all outgoing traffic if the tunnel goes down, so you don't leak your real IP. Works alongside Tailscale.

## What's inside

```
vpn              the control script
killswitch.nft   nftables kill switch rules
vpn-control      sudoers file (passwordless sudo for vpn)
install.sh       copies files to the right places
```

## Requirements

- [wgcf](https://github.com/ViRb3/wgcf) configured and generating `/etc/wireguard/wgcf.conf`
- `nftables` with `/etc/nftables.conf` including `/etc/nftables.d/*.nft`
- user in the `wheel` group (Arch) or `sudo` group (Debian/Ubuntu)
- Tailscale is optional, the rules handle both cases

## Install

```bash
git clone https://github.com/mvadel136/warp-killswitch
cd warp-killswitch
sudo bash install.sh
```

## Usage

```
vpn up       load kill switch, start tunnel
vpn down     stop tunnel, remove kill switch
vpn restart  restart tunnel without dropping kill switch
vpn status   show tunnel + kill switch state and public IP
```

## How it works

`vpn up` loads the nftables rules first, then brings up wgcf. The rules drop all outgoing traffic by default and only allow packets through the `wgcf` interface. So if the tunnel crashes, traffic stops instead of falling back to your real IP.

`vpn restart` only restarts the WireGuard interface, the kill switch stays loaded the whole time.

The Tailscale rules use `oifname` instead of `oif` so nftables loads cleanly even when the `tailscale0` interface doesn't exist yet.

## Note on privacy

WARP routes your traffic through Cloudflare. Cloudflare sees your traffic. This hides you from your ISP and public networks, not from Cloudflare. If you need actual privacy, use Mullvad or ProtonVPN.
