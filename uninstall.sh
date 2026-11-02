#!/usr/bin/env bash
# Remove the plugin and CLI. Your NetworkManager pvpn-* connections are NOT touched.
set -euo pipefail
id="allandehn.pvpn"
dest="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$id"

omarchy plugin disable "$id" 2>/dev/null || true
rm -rf -- "$dest"
rm -f -- "$HOME/.local/bin/pvpn"
rm -rf -- "${XDG_STATE_HOME:-$HOME/.local/state}/pvpn"
omarchy-restart-shell >/dev/null 2>&1 &
echo "Removed. To also remove a VPN profile: nmcli connection delete pvpn-xx"
