# Proton VPN

A shield on the Omarchy bar for the official
[Proton VPN CLI](https://protonvpn.com/support/linux-cli): connect, see where
your traffic goes, and switch NetShield and the kill switch without a terminal.

- **The shield** is filled while a tunnel is up, pulses while connecting, and
  names the server on hover. **Right click** connects (to the fastest server, or
  to `quickConnect`) or disconnects.
- **The panel** shows the server, its city, load and protocol, and your exit IP
  as Proton sees it. While disconnected it tells you your real IP is visible.
- **Connect** to the fastest server, Secure Core, P2P, Tor or a random one; to a
  favorite country in one click; or type a country, a city or a server ID
  (`CH#242`) in the field. `/` jumps to it.
- **NetShield** (off, malware, malware + ads and trackers) and the **kill switch**
  (changed only while disconnected; the CLI insists).
- A notification when the tunnel comes up or goes down, whoever brought it there.

State comes from NetworkManager (`nmcli monitor`), so it stays right even when
you connect from a terminal. The CLI calls its connections `ProtonVPN <server>`
on `proton0`; that is all this looks for.

## Install

```bash
omarchy pkg add proton-vpn-cli
omarchy plugin add https://github.com/loneycoffee/omarchy-proton-vpn.git --enable
```

Then click the shield and **Sign in…**: a terminal asks for your username,
password and 2FA code (the CLI keeps the session in your keyring). The CLI
cannot run alongside the Proton VPN GTK app.

Open the panel from a keybinding with
`omarchy-shell shell toggle proton-vpn`.

## Settings

In `~/.config/omarchy/shell.json`, on the `proton-vpn` bar entry:

| Key            | Default                    | Meaning                                                    |
|----------------|----------------------------|------------------------------------------------------------|
| `quickConnect` | `""`                       | What right click connects to: `CH`, `Zurich`, `CH#242`; empty for fastest |
| `favorites`    | `["CH", "NL", "US", "JP"]` | Country codes shown as one-click buttons                   |

## Keys in the panel

`enter` connect/disconnect · `f` fastest · `d` disconnect · `/` search ·
`r` refresh · `esc` close

## Command line

```
pvpn state                 JSON: is a Proton VPN tunnel up, and to which server
pvpn details               JSON: account, load, protocol, settings, exit IP
pvpn countries             JSON: every country with servers (cached for a day)
pvpn connect [ARGS...]     protonvpn connect ARGS..., as JSON {ok, message}
pvpn disconnect            protonvpn disconnect, as JSON {ok, message}
pvpn set FEATURE VALUE     protonvpn config set FEATURE VALUE, as JSON
pvpn signin                interactive: ask for the username, then sign in
```

The exit IP comes from `api.protonvpn.ch/vpn/location`, Proton's own endpoint;
nothing else is contacted.
