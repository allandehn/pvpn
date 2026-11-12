#!/usr/bin/env bash
# Install the Proton VPN bar plugin and the pvpn CLI for the current user.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
id="allandehn.pvpn"
dest="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$id"
bindir="$HOME/.local/bin"

command -v nmcli >/dev/null || { echo "nmcli (NetworkManager) is required" >&2; exit 1; }
command -v omarchy >/dev/null || { echo "Omarchy is required" >&2; exit 1; }

mkdir -p "$dest" "$bindir"
install -m 644 "$here/manifest.json" "$here/Panel.qml" "$here/oklch.js" "$dest/"
install -m 755 "$here/bin/pvpn" "$bindir/pvpn"

omarchy plugin enable "$id" || true
echo "Restarting the Omarchy shell so the plugin loads…"
omarchy-restart-shell >/dev/null 2>&1 &
echo "Done. Plugin: $dest  CLI: $bindir/pvpn"
case ":$PATH:" in
  *":$bindir:"*) echo "Next: run  pvpn import" ;;
  *) echo "Note: $bindir is not on your PATH, so run it as  $bindir/pvpn import"
     echo "(or add $bindir to PATH in ~/.bashrc)." ;;
esac
