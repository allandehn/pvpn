# Proton VPN for the Omarchy bar (`allandehn.pvpn`)

A small [Omarchy](https://omarchy.org) bar plugin, plus the `pvpn` CLI it uses as its engine, that shows and switches
**Proton VPN WireGuard connections managed by NetworkManager**. No Proton app, no daemon,
no background polling: it listens to `nmcli monitor` and only runs `nmcli` when something changes.

> **Unofficial.** This project is not affiliated with, endorsed by, or supported by Proton AG or Proton VPN.
> "Proton" and "Proton VPN" are trademarks of Proton AG. It only drives standard NetworkManager
> WireGuard profiles that you import yourself.

> **No kill switch.** If the tunnel drops, your traffic goes out **unprotected** over your normal
> connection until you reconnect. Check DNS after connecting with `resolvectl status` and a
> leak test such as <https://dnsleaktest.com>.

## Features

- Bar icon: filled shield when connected, dimmed crossed shield when off. Tooltip `Proton VPN · Denmark` / `Proton VPN · Off`.
- **Left click** opens a native Omarchy panel; **right click** toggles on/off; **middle click** refreshes.
- Panel: on/off switch, one row per connection (country name), connected row in accent colour.
  Click a row (or move with `hjkl`/arrows and press `Enter`) to **switch** to it, or **reconnect** it if it is already active.
  `t` toggles, `r` reconnects, `Esc` closes. Rows are greyed out while the VPN is off; clicking one turns it on.
- The connection is verified (NetworkManager state + a ping through the tunnel) before it is reported as connected.
- Desktop notifications: `Connected to Estonia`, `Reconnected to Denmark`, `Proton VPN off`, or
  `Couldn't connect to Estonia` – in which case the previous connection is restored (or it stays off).
- **Boot follows the last state:** connecting sets `autoconnect=yes` on that `pvpn-*` profile only (and `no` on
  the other `pvpn-*` profiles); turning the VPN off sets `autoconnect=no` on all of them. The last used profile is
  remembered in `$HOME/.local/state/pvpn/last`. Non-`pvpn-*` connections are never touched.
- Theme-aware: uses Omarchy's theme tokens, so it follows your theme.

## Requirements

- Omarchy with its Quickshell-based bar (plugin support)
- NetworkManager with WireGuard support, and `nmcli`
- A Nerd Font (Omarchy's default JetBrainsMono Nerd Font works)
- `notify-send` (libnotify) for notifications
- A Proton VPN account that can create WireGuard configurations

## 1. Create and import your WireGuard profiles (manual, once per country)

The plugin only lists NetworkManager connections that are **type `wireguard`** and whose **name starts with `pvpn-`**.
Name them `pvpn-<country code>`, e.g. `pvpn-dk`, `pvpn-ee`, `pvpn-us-east` (the part after the country code is shown in brackets).

1. On <https://account.protonvpn.com> go to **Downloads → WireGuard configuration**, pick a server and download the `.conf`.
   Download it into a private temporary folder, not a synced one:

   ```bash
   tmp=$(mktemp -d) && chmod 700 "$tmp" && echo "$tmp"   # save the .conf here
   ```

   A config looks like this (never share yours):

   ```ini
   [Interface]
   PrivateKey = <redacted>
   Address = <address from your config>
   DNS = <dns from your config>

   [Peer]
   PublicKey = <server public key>
   Endpoint = 203.0.113.1:51820
   AllowedIPs = 0.0.0.0/0
   ```

2. Import it, rename it, and switch off autoconnect (the plugin will manage that later):

   ```bash
   nmcli connection import type wireguard file "$tmp/DK-123.conf"
   nmcli connection modify DK-123 connection.id pvpn-dk     # the imported name = the file name without .conf
   nmcli connection modify pvpn-dk connection.interface-name pvpn-dk   # the bar watches for "pvpn-" names
   nmcli connection modify pvpn-dk connection.autoconnect no
   ```

3. **Delete the downloaded file** – it contains your private key:

   ```bash
   shred -u "$tmp"/*.conf && rmdir "$tmp"
   ls ~/Downloads/*.conf 2>/dev/null   # check for stray copies, shred them too
   ```

   On SSDs neither `rm` nor `shred` guarantees the data is physically wiped; full-disk encryption is what really protects it.
   Never keep configs in cloud-synced folders (Dropbox, Syncthing, Nextcloud, …).

   After import the key lives in `/etc/NetworkManager/system-connections/` (readable by root only).

4. If a device is lost or a key may have leaked, **revoke that configuration** on account.protonvpn.com.

To remove a profile later:

```bash
nmcli connection delete pvpn-dk
```

### Other VPN apps

Don't run Mullvad, the official Proton app or another VPN at the same time. Their firewalls/"lockdown" modes can
block the WireGuard tunnel (Mullvad's did). Disconnect them, switch off their auto-connect and lockdown / kill switch,
or stop their daemon (e.g. `sudo systemctl disable --now mullvad-daemon`).

## 2. Install

```bash
git clone https://github.com/allandehn/omarchy-pvpn.git
cd omarchy-pvpn
./install.sh
```

`install.sh` copies the plugin to `~/.config/omarchy/plugins/allandehn.pvpn/`, the CLI to `~/.local/bin/pvpn`,
runs `omarchy plugin enable allandehn.pvpn`, and restarts the shell.

Manual install, if you prefer:

```bash
mkdir -p ~/.config/omarchy/plugins/allandehn.pvpn
cp manifest.json Panel.qml ~/.config/omarchy/plugins/allandehn.pvpn/
install -m 755 bin/pvpn ~/.local/bin/pvpn      # required: the plugin calls it
omarchy plugin enable allandehn.pvpn
omarchy-restart-shell                          # required: plugin edits only load after a shell restart
```

## Uninstall

```bash
./uninstall.sh
```

This disables and removes the plugin, the CLI and the small state file. Your `pvpn-*` NetworkManager profiles stay;
delete them with `nmcli connection delete pvpn-xx`.

## CLI

The plugin calls `pvpn` for every change, so the bar and the terminal behave identically; install both (install.sh does).

```text
pvpn                 menu (Walker, or fzf)
pvpn status          connected profile and boot profile
pvpn list            pvpn-* WireGuard profiles
pvpn up pvpn-dk      connect, verify, roll back on failure (and make it the boot profile)
pvpn reconnect NAME  reconnect
pvpn toggle          off, or back on with the last used profile
pvpn down            disconnect (and clear autoconnect on all pvpn-* profiles)
pvpn boot [NAME|none]
```

pvpn makes no network requests except a ping to 1.1.1.1 through the tunnel after connecting, to check that it carries traffic.

## License

MIT – see [LICENSE](LICENSE).
