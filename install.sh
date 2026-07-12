#!/usr/bin/env bash
set -euo pipefail

[ "$EUID" -ne 0 ] && exec sudo "$0" "$@"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TARGET_USER="${SUDO_USER:-${USER:-}}"

echo "==> checking prerequisites"
MISSING=0
for bin in nft wg-quick systemctl; do
    if ! command -v "$bin" >/dev/null 2>&1; then
        echo "  missing: $bin" >&2
        MISSING=1
    fi
done
if [ "$MISSING" -eq 1 ]; then
    echo "install aborted: install nftables and wireguard-tools first" >&2
    exit 1
fi
if [ ! -f /etc/wireguard/wgcf.conf ]; then
    echo "  /etc/wireguard/wgcf.conf not found, set up wgcf before running vpn up"
fi

echo "==> installing vpn control script"
cp vpn /usr/local/bin/vpn
chmod +x /usr/local/bin/vpn

echo "==> installing kill switch rules"
mkdir -p /etc/nftables.d/
cp killswitch.nft /etc/nftables.d/killswitch.nft

echo "==> configuring passwordless sudo"
ADMIN_GROUP=""
if [ -n "$TARGET_USER" ] && id -nG "$TARGET_USER" 2>/dev/null | grep -qw wheel; then
    ADMIN_GROUP=wheel
elif [ -n "$TARGET_USER" ] && id -nG "$TARGET_USER" 2>/dev/null | grep -qw sudo; then
    ADMIN_GROUP=sudo
elif getent group wheel >/dev/null 2>&1; then
    ADMIN_GROUP=wheel
elif getent group sudo >/dev/null 2>&1; then
    ADMIN_GROUP=sudo
else
    echo "  no wheel or sudo group found on this system" >&2
    echo "  edit vpn-control by hand and copy it to /etc/sudoers.d/vpn-control" >&2
    exit 1
fi
echo "  using group: $ADMIN_GROUP"

SUDOERS_TMP="$(mktemp)"
echo "%${ADMIN_GROUP} ALL=(root) NOPASSWD: /usr/local/bin/vpn" > "$SUDOERS_TMP"
if ! visudo -cf "$SUDOERS_TMP" >/dev/null; then
    echo "  generated sudoers rule failed validation, not installing it" >&2
    rm -f "$SUDOERS_TMP"
    exit 1
fi
cp "$SUDOERS_TMP" /etc/sudoers.d/vpn-control
chmod 440 /etc/sudoers.d/vpn-control
rm -f "$SUDOERS_TMP"

if [ -n "$TARGET_USER" ]; then
    if sudo -l -U "$TARGET_USER" 2>/dev/null | grep -qF "/usr/local/bin/vpn"; then
        echo "  verified: $TARGET_USER can run vpn without a password"
    else
        echo "  installed the rule but could not verify it took effect for $TARGET_USER" >&2
        echo "  check that /etc/sudoers actually reads /etc/sudoers.d (sudo visudo, look for an includedir/include line)" >&2
    fi
fi

echo "==> checking /etc/nftables.conf (boot persistence only, vpn up loads killswitch.nft directly)"
NFT_CONF=/etc/nftables.conf
INCLUDE_LINE='include "/etc/nftables.d/*.nft";'
ACTIVE_RE='^[[:space:]]*include[[:space:]]+"/etc/nftables\.d/\*\.nft"[[:space:]]*;?[[:space:]]*$'
if [ ! -f "$NFT_CONF" ]; then
    printf '#!/usr/sbin/nft -f\n\nflush ruleset\n\n%s\n' "$INCLUDE_LINE" > "$NFT_CONF"
    chmod 644 "$NFT_CONF"
    echo "  created $NFT_CONF with the include line"
elif grep -qE "$ACTIVE_RE" "$NFT_CONF"; then
    echo "  include line already active"
else
    BACKUP="$NFT_CONF.bak.$(date +%s)"
    cp "$NFT_CONF" "$BACKUP"
    printf '\n%s\n' "$INCLUDE_LINE" >> "$NFT_CONF"
    echo "  no active include line found, added one (backup: $BACKUP)"
    echo "  any pre-existing commented-out include lines were left as-is"
fi

if ! CHECK_OUT="$(nft -c -f "$NFT_CONF" 2>&1)"; then
    echo "  $NFT_CONF does not pass nft -c -f, fix it before running vpn up:" >&2
    echo "$CHECK_OUT" >&2
fi

echo "==> enabling services for boot persistence"
for unit in nftables.service wg-quick@wgcf.service; do
    if systemctl enable "$unit" >/dev/null 2>&1; then
        echo "  enabled $unit"
    else
        echo "  could not enable $unit, enable it manually if you want boot persistence"
    fi
done

echo ""
echo "install complete"
echo "  vpn script:    /usr/local/bin/vpn"
echo "  kill switch:   /etc/nftables.d/killswitch.nft"
echo "  passwordless:  %${ADMIN_GROUP}"
echo ""
echo "run: vpn up"
