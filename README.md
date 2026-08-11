<div align="center">

<pre>
╔╗╔╔═╗╦═╗╔╦╗  ╦  ╦ ╦╔╗╔═╗ ╦
║║║║ ║╠╦╝ ║║  ║  ╚╦╝║║║╔╩╦╝
╝╚╝╚═╝╩╚══╩╝  ╩═╝ ╩ ╝╚╝╩ ╚═
</pre>

### NordLynx Manager
**Multi-Location SOCKS5 Proxy Factory for Marzban / Pasarguard**

Один script. یک اسکریپت. One menu.
Spin up a NordVPN **NordLynx** container per country — each with its own local SOCKS5 port,
ready to drop straight into your Xray outbounds and routing rules.

<br>

![Bash](https://img.shields.io/badge/Bash-5.0%2B-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-required-2496ED?style=for-the-badge&logo=docker&logoColor=white)
![NordLynx](https://img.shields.io/badge/NordLynx-WireGuard-4687FF?style=for-the-badge&logo=wireguard&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-8A2BE2?style=for-the-badge)
![Zero deps](https://img.shields.io/badge/Dependencies-zero-success?style=for-the-badge)

<br>

**[English](#english)** · **[فارسی](#فارسی)**

</div>

---

<a name="english"></a>

## What you get

```
  ┌─ your server ────────────────────────────────────────────────┐
  │                                                              │
  │   Marzban / Pasarguard  ──routing──┬─▶ 127.0.0.1:1081  🇺🇸    │
  │                                    ├─▶ 127.0.0.1:1082  🇹🇷    │
  │                                    ├─▶ 127.0.0.1:1083  🇦🇪    │
  │                                    ├─▶ 127.0.0.1:1084  🇦🇺    │
  │                                    └─▶ 127.0.0.1:1085  🇳🇱    │
  │                                          │                   │
  │        each port = 1 docker container = 1 NordLynx tunnel    │
  └──────────────────────────────────────────────────────────────┘
```

Every port is a live SOCKS5 endpoint whose traffic exits in that country.
Route per-domain, per-user or per-inbound however you like.

## The menu

```
  docker ✔   token ✔   image ✔   locations 5   watchdog ●   default NordLynx/UDP

  MAIN MENU

    1  Install prerequisites (Docker, tun, tools)
    2  Access tokens (add / remove / list)
    3  Build the proxy image

    4  Create a new location
    5  Quick setup — pick any of the classic 5 locations
    6  Location settings (country, protocol, port, toggles)

    7  Live status dashboard
    8  Test all proxies (real exit IP + country)
    9  View a container's logs
   10  Restart / stop / start a location
   11  Delete a location

   12  Export Marzban / Pasarguard outbounds
   13  WireGuard tools (private key, .conf export)
   14  Auto-healer (watchdog cron)
   15  Backup / restore configuration
   16  Defaults for new locations
   17  Telegram bot (remote control)
   18  Language / Zaban / Язык / 语言
   19  Port map (see and free busy ports)
   20  Update from GitHub

    0  Quit
```

## Busy ports (menu 19)

A port conflict never just fails any more. Whenever a port is taken — while adding a
location, during quick setup, or when changing a port — the script tells you exactly
*who* holds it and offers a way out:

```
  ▲ Port 1081 is taken by: container nord-1-usa (managed by this script)

    1  Free that port (remove the container) and continue
    2  Use the next free port instead  → 1086
    3  Type another port
    0  Skip this location
```

Foreign containers (from an older manual setup, for example) ask for an extra
confirmation before removal. Host processes are reported but never touched.

Menu **19** shows the whole neighbourhood at a glance and can free a port on demand:

```
  PORT    STATE        OWNER
  1080    free
  1081    ours         nord-1-usa
  1082    foreign      old-manual-turkey
  1090    host proc    "nginx",pid=9,fd=6
```

## Multiple access tokens (menu 2)

Tokens live in a named vault at `/opt/nordlynx-manager/tokens.tsv` (mode 600), so one
server can run locations from several Nord accounts:

```
  #    NAME       TOKEN            USED BY
  1    main       a1b2c3…9f4e      3 location(s)
  2    backup     77aa12…0c31      1 location(s)
  3    client-a   e5f0d9…44b7      0 location(s)
```

Every new location asks which token to build with, and the choice is stored on the
container as a label — so the dashboard and the bot always show which account a
location belongs to. A pre-2.1 single-token file is imported automatically as `default`.

## Telegram bot (menu 17)

Full remote control from your phone. Set the bot token from [@BotFather](https://t.me/BotFather),
add one or more admin IDs (get yours from [@userinfobot](https://t.me/userinfobot)), then
install — it runs as a systemd service (`nordlynx-bot`) and survives reboots.

```
  NordLynx Manager
  🔑 tokens: 3     📦 locations: 5  (running: 5)

  [ 🔑 Access tokens ]   [ ➕ New location ]
  [ 📋 Locations     ]   [ ♻️ Refresh      ]
```

**🔑 Access tokens** — list with masked values and usage count, add one (name, then the
token itself), remove one.

**➕ New location** — a four-step wizard: pick token → pick country → pick city (pulled live
from the NordVPN CLI, or "any") → pick a port from suggested free ones or type your own.
Then it builds and reports the real exit IP.

**📋 Locations** — every container as a button. Tapping one shows:

```
  nord-2-turkey

  🔑 token: main
  🌍 configured: Turkey / Istanbul
  🔌 protocol: NordLynx / UDP
  🧦 socks5: 127.0.0.1:1082 → container 1080
  📦 docker: running
  ⏱ uptime: 3d 4h 12m

  NordVPN
  status: Connected
  connected to: Turkey / Istanbul
  server: tr61.nordvpn.com

  [ 🔢 Change port ]  [ 🌍 Change location ]
  [ 📤 Export socks outbound ]
  [ ♻️ Refresh ]      [ ⬅️ Back ]
```

Changing the port or the country rebuilds the container under the **same name**, then
drops you back at the main menu — no dead-end screens.

> Only the listed admin IDs can do anything; anyone else gets their own ID echoed back
> and nothing else. The bot handles tokens in chat, so delete the message containing a
> token after sending it — Telegram keeps chat history.

Everything is number-driven. No file editing, no `docker run` copy-paste.

## Quick setup (menu 5)

Not all-or-nothing — pick exactly what you want, and busy ports are flagged before
you choose:

```
    1 ! 🇺🇸 United_States        → 127.0.0.1:1081  (port busy — container nord-1-usa)
    2   🇹🇷 Turkey               → 127.0.0.1:1082
    3   🇦🇪 United_Arab_Emirates → 127.0.0.1:1083
    4   🇦🇺 Australia            → 127.0.0.1:1084
    5   🇳🇱 Netherlands          → 127.0.0.1:1085

  Pick what to build: a single number (3), a list (1,3,5), a range (1-3) or all.
  ? Which locations? [all]:
```

Containers are started **all at once** and then watched together, so five locations
take about as long as one instead of five times as long:

```
  CONTAINER                    COUNTRY                PORT    STATE
  nord-1-united-states         United_States          1081    connected
  nord-2-turkey                Turkey                 1082    connecting…
  nord-3-united-arab-emirates  United_Arab_Emirates   1083    connected
```

Anything that fails gets its last log lines printed and can be retried on the spot —
NordVPN hands out a different server each attempt.

## Per-location settings (menu 6)

Pick a container, change anything, hit **A** to apply — it rebuilds with the same
name and host port, so your Marzban config never has to change.

```
  Current settings
   Country            🇹🇷 Turkey
   Technology         NordLynx
   Transport          UDP (NordLynx)
   socks5             127.0.0.1:1082 → container 1080
   Auto-connect       enabled
   LAN discovery      enabled
   Analytics          disabled

    1  Country               Turkey
    2  Technology            NordLynx        ← NordLynx or OpenVPN
    3  Transport             UDP (NordLynx)  ← UDP / TCP, OpenVPN only
    4  Host port             1082            ← change the SOCKS5 port
    5  Container port        1080
    6  Bind address          127.0.0.1
    7  Auto-connect          enabled         ← toggle
    8  LAN discovery         enabled         ← toggle
    9  Analytics             disabled        ← toggle

    A  Apply — recreate the container
```

Menu **16** sets the same knobs as defaults for every *new* location.

## WireGuard tools (menu 13)

For NordLynx locations the script can read the live tunnel and hand you a full
WireGuard config — private key, peer key, endpoint, address — so you can use that
same Nord slot on a phone or router:

```
    1  Show private key
    2  Show full WireGuard config
    3  Save config to a file          → /opt/nordlynx-manager/exports/<name>.conf (mode 600)
    4  Show QR code                   → scan straight into the WireGuard app
    5  Show raw interface state (wg show)
```

Also available headless: `sudo nordlynx --wg nord-2-turkey`

> A WireGuard private key is a **full credential**. Anyone holding it can use your
> VPN slot. Never commit exported `.conf` files, and clear the screen after showing a QR.

## Features

| | |
|---|---|
| 🎛️ **Pure Bash TUI** | ANSI colors, spinners, progress bars. Zero dependencies — works over raw SSH |
| 🔌 **NordLynx or OpenVPN** | Per location. OpenVPN adds a **UDP / TCP** transport choice for filtered networks |
| 🎚️ **Every Nord switch exposed** | Auto-connect, LAN discovery, analytics — toggled per container, persisted in its env |
| 🔢 **Any SOCKS port** | Host port and container port both editable, per location |
| 🔑 **WireGuard export** | Private key, ready-made `.conf`, and a QR code straight from a running NordLynx tunnel |
| 🗝️ **Named token vault** | Several Nord accounts on one server; each location remembers which token built it |
| 🤖 **Telegram bot** | Manage tokens, build locations, inspect and rebuild containers from your phone |
| 🏙️ **City selection** | Cities pulled live from the NordVPN CLI, not a hardcoded list |
| 🌍 **6 UI modes** | English · Русский · 简体中文 · Finglish · فارسی (pre-shaped) · فارسی (raw), with live previews so you pick what your terminal actually renders |
| 🏗️ **Self-building image** | Writes its own `Dockerfile` + `entrypoint.sh`, builds Debian + NordVPN CLI + microsocks |
| 🔐 **Safe token handling** | Hidden input, `chmod 600`, never echoed in full, never in Git |
| ⚡ **One-key setup** | The classic 5 locations in a single confirmation |
| 🗺️ **30 countries + custom** | Presets with flags, plus free-text for anything else in Nord's catalog |
| 🔁 **Change country in place** | Same host port, container rebuilt with the new `NORD_COUNTRY` |
| 📊 **Live dashboard** | Docker state, VPN state, ports, host listeners |
| 🧪 **Real exit-IP test** | Probes each proxy via `ipinfo.io` and prints IP + geo verdict |
| 📤 **Xray export** | Ready-to-paste `outbounds.json` + routing skeleton |
| 🩺 **Auto-healer** | Optional `*/5` cron watchdog restarts any proxy whose exit dies |
| 💾 **Backup / restore** | Manifest of every location, restorable onto a fresh server |

## Requirements

- Ubuntu 20.04+ / Debian 11+, root or sudo
- NordVPN subscription + **access token**
  → Nord Account → Services → NordVPN → Manual setup → *Generate new token*
- Docker and `/dev/net/tun` — the script installs/creates both for you

## Install

```bash
git clone https://github.com/sepehrwwe49/nordlynx.git
cd nordlynx
chmod +x nordlynx-manager.sh
sudo ./nordlynx-manager.sh
```

Or the one-liner — it bootstraps itself:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/sepehrwwe49/nordlynx/main/nordlynx-manager.sh)
```

Run from a pipe, the script notices it has no file on disk, downloads
`nordlynx-manager.sh` + `nordlynx-bot.sh` into `/opt/nordlynx-manager/src/`,
syntax-checks both, links itself to `/usr/local/bin/nordlynx`, then re-execs. From
then on you just run:

```bash
sudo nordlynx
```

Menu **19** (or `sudo nordlynx --update`) pulls the latest version from GitHub later,
and restarts the Telegram bot service if it's installed.

Put it on your `PATH`:

```bash
sudo ./nordlynx-manager.sh --install    # then just:  sudo nordlynx
```

## First run — happy path

```
1  →  Install prerequisites      Docker, /dev/net/tun, curl, jq
2  →  Set your NordVPN token     hidden input, saved with mode 600
3  →  Build the proxy image      a few minutes, once
5  →  Quick setup: 5 locations   USA · Turkey · UAE · Australia · Netherlands
8  →  Test all proxies           confirm each exits in the right country
12 →  Export outbounds           paste into Marzban / Pasarguard
```

## Wiring into Marzban / Pasarguard

Menu option **12** writes `/opt/nordlynx-manager/outbounds.json`:

```json
[
  {
    "tag": "NORD-UNITED_STATES",
    "protocol": "socks",
    "settings": { "servers": [ { "address": "127.0.0.1", "port": 1081 } ] },
    "streamSettings": { "network": "tcp" }
  },
  {
    "tag": "NORD-TURKEY",
    "protocol": "socks",
    "settings": { "servers": [ { "address": "127.0.0.1", "port": 1082 } ] },
    "streamSettings": { "network": "tcp" }
  }
]
```

Then route to it:

```json
{ "type": "field", "domain": ["geosite:netflix"], "outboundTag": "NORD-UNITED_STATES" }
{ "type": "field", "domain": ["geosite:openai"],  "outboundTag": "NORD-TURKEY" }
```

> **If Marzban runs inside its own Docker network**, `127.0.0.1` won't reach the host.
> Either bind the proxies to the docker bridge IP (the script asks for a bind address),
> or add `extra_hosts: ["host.docker.internal:host-gateway"]` to Marzban's compose and
> dial `host.docker.internal`.

## CLI mode (cron / automation)

```bash
sudo nordlynx --list          # managed locations (TSV)
sudo nordlynx --status        # status table
sudo nordlynx --test          # exit-IP test for every proxy
sudo nordlynx --export        # regenerate outbounds.json
sudo nordlynx --wg NAME       # print a location's WireGuard config
sudo nordlynx --heal          # one watchdog pass
sudo nordlynx --ports         # port map 1080–1100
sudo nordlynx --cleanup       # remove dead / duplicate containers
sudo nordlynx --debug         # spawn a throwaway container and dump full diagnostics
sudo nordlynx --update        # pull the latest version from GitHub
sudo nordlynx --bot           # run the Telegram bot in the foreground
```

## How a container is built

```bash
docker run -d \
  --name nord-1-united-states \
  --restart unless-stopped \
  --cap-add=NET_ADMIN \
  --device=/dev/net/tun \
  -p 127.0.0.1:1081:1080 \
  -e NORD_COUNTRY=United_States \
  -e NORD_TOKEN='***' \
  -e NORD_TECH=NordLynx \
  -e NORD_PROTO=UDP \
  -e NORD_AUTOCONNECT=on \
  -e NORD_LAN=on \
  -e NORD_ANALYTICS=off \
  -e SOCKS_PORT=1080 \
  --label nlm.managed=1 \
  nordlynx-proxy:latest
```

Every knob is an env var, so settings survive restarts. Inside, `entrypoint.sh`
runs seven stages and fails loudly if any break:

```
1/7  start nordvpn service           5/7  auto-connect on/off
2/7  wait for nordvpnd.sock          6/7  connect + poll until "Status: Connected"
3/7  login with access token         7/7  exec microsocks on 0.0.0.0:$SOCKS_PORT
4/7  technology · transport · analytics · lan-discovery · allowlist
```

microsocks starts **only after** the tunnel is confirmed up — so a reachable port always
means a working VPN exit, never a silent leak to your server's real IP.

## Why the containers run privileged

While connecting, the NordVPN daemon writes `net.ipv6.conf.all.disable_ipv6` through
`/proc/sys`. Docker mounts `/proc/sys` read-only, so the write fails and the daemon
aborts the whole connection:

```
failed to connect to usXXXX.nordvpn.com :
sysctl: permission denied on key "net.ipv6.conf.all.disable_ipv6"
```

`--cap-add=NET_ADMIN`, `NET_RAW`, `SYS_MODULE` and the `src_valid_mark` sysctl are all
necessary but not sufficient — only `--privileged` makes `/proc/sys` writable. So every
location is created with `--privileged` plus `--sysctl net.ipv6.conf.all.disable_ipv6=1`.

You can turn it off per location (menu 6 → item 12) or globally (menu 16 → item 8), but
NordVPN will then fail to connect on current versions.

> A privileged container can reach the host kernel. That is a real trade-off: you are
> trusting the NordVPN client and this image with root-equivalent access to the box.
> Run it on a machine where that is acceptable, and keep the SOCKS ports bound to
> `127.0.0.1`.

## Security

- The access token is a credential. Stored at `/opt/nordlynx-manager/.token` (0600) and in each
  container's env. **Never commit it.** If it leaks, revoke it in Nord Account and generate a new one.
- Default bind is `127.0.0.1`. Binding `0.0.0.0` publishes an **open, unauthenticated** SOCKS5
  proxy to the whole internet — firewall it, or don't do it.
- Backup archives contain the token. Treat `*.tar.gz` as secrets.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Couldn't find /run/nordvpn/nordvpnd.sock` | Container needs `--cap-add=NET_ADMIN` + `/dev/net/tun` — rerun menu option 1 |
| Login failed | Token expired/wrong — regenerate, menu option 2, then recreate containers |
| Log stops at `[3/7] Logging in…`, `nordvpn account` says "You're not logged in" | NordVPN CLI 4.x/5.x asks for a privacy-consent decision on first run and blocks every other command until it gets one. It only accepts the full words `yes`/`no` — `y`/`n` loop forever on `Invalid response`. v2.5.2 answers it correctly before logging in |
| `We couldn't reach System Daemon` | The daemon socket appears before the daemon can answer. v2.4.0 polls until it really responds, and restarts the service once if it doesn't |
| `We couldn't connect you to the VPN` and the daemon log says `nft failed with: exec: "nft": executable file not found` | The NordVPN 5.x daemon builds its firewall rules with **nftables**, so the `nft` binary must exist in the image. Fixed in v2.5.1 — rebuild the image (menu 3) |
| Log shows `Connecting to NordVPN is already in progress.` and the location never comes up | Auto-connect was armed before our own connect, so the daemon and the script fought over the tunnel — and the retry loop's `disconnect` killed the daemon's attempt. Fixed in v2.8.1: auto-connect is armed only after a successful connect, and an in-flight attempt is never interrupted |
| `We couldn't connect you to the VPN`, daemon log says `sysctl: permission denied on key "net.ipv6.conf.all.disable_ipv6"` | Docker mounts `/proc/sys` read-only. Fixed in v2.6.0 — containers now run with `--privileged`. Rebuild and recreate |
| `We couldn't connect you to the VPN` on NordLynx | The **host** kernel needs the `wireguard` module — a container cannot provide it. Menu 1 installs and loads it. If your VPS kernel has no WireGuard support, containers automatically fall back to OpenVPN (v2.4.0) |
| Updated the script but the container log looks unchanged | The entrypoint is baked **into the image**. Run menu 3 to rebuild, then recreate the containers. Since v2.3.3 the script detects this itself and offers the rebuild — the health line shows `image ▲` when the image is older than the script |
| Stuck on `Disconnected` | Country name must match Nord's spelling with underscores: `United_Arab_Emirates` |
| Wrong country IP | Recreate that location (menu 6); Nord occasionally lands on a neighbouring PoP |
| `Port already in use` | `ss -lntp \| grep :1085` then remove the stale container |
| Build fails on `apt` | Server DNS/network blocked — check `docker run --rm debian:bookworm-slim apt-get update` |
| `unistd.h: No such file or directory` while compiling microsocks | Fixed in v2.1.1 — `gcc` only *recommends* `libc6-dev`, which `--no-install-recommends` skipped. Update the script and rerun menu 3 |
| Stuck on "Waiting for VPN tunnel" then timeout | v2.2.1 adds the flags WireGuard needs in a container (`NET_RAW`, `src_valid_mark=1`) and turns Nord's own firewall/killswitch off. Update, delete the stuck container, rebuild. The timeout now prints the container log automatically |
| `unable to remove filesystem: unlinkat …/resolv.conf: operation not permitted`, containers stuck in `Dead` | The NordVPN client sets the **immutable** flag (`chattr +i`) on `resolv.conf` to protect its DNS. If the container dies with the flag set, Docker can't unlink the file. v2.7.2 clears it automatically (menu 20). Manually: `chattr -i /var/lib/docker/containers/*/resolv.conf` |
| Several containers on the same port, some `dead`/`exited` | A dead container doesn't listen, so the port looks free and a duplicate gets built. v2.7.0 removes the old one first and menu 20 cleans up whatever is left |
| Port already busy | v2.3.0 shows who holds it and offers to free it, use the next free port, type another, or skip. Menu 19 maps ports 1080–1100 |

## Uninstall

```bash
docker ps -aq --filter label=nlm.managed=1 | xargs -r docker rm -f
docker rmi nordlynx-proxy:latest
sudo rm -rf /opt/nordlynx-manager /usr/local/bin/nordlynx /usr/local/bin/nordlynx-healer.sh
sudo crontab -l | grep -v nordlynx-healer | sudo crontab -
```

---

<a name="فارسی"></a>

<div dir="rtl" align="right">

## فارسی

### این چیه؟

برای هر کشور یک کانتینر NordVPN با پروتکل **NordLynx** بالا می‌آورد و روی یک پورت جداگانه
**SOCKS5** می‌دهد. بعد در **مرزبان** یا **پاسارگارد** برای هر پورت یک اوتباند از نوع `socks`
می‌سازی و در Routing استفاده می‌کنی — مثلاً نتفلیکس از آمریکا، ChatGPT از ترکیه.

```
مرزبان / پاسارگارد ──routing──┬─▶ 127.0.0.1:1081  آمریکا
                              ├─▶ 127.0.0.1:1082  ترکیه
                              ├─▶ 127.0.0.1:1083  امارات
                              ├─▶ 127.0.0.1:1084  استرالیا
                              └─▶ 127.0.0.1:1085  هلند
```

### پیش‌نیاز

- اوبونتو ۲۰.۰۴ به بالا یا دبیان ۱۱ به بالا، با دسترسی root
- اشتراک NordVPN و **اکسس‌توکن**
  مسیر: Nord Account ← Services ← NordVPN ← Manual setup ← Generate new token
- داکر و `/dev/net/tun` — خود اسکریپت نصب و ایجادشان می‌کند

### نصب

```bash
git clone https://github.com/sepehrwwe49/nordlynx.git
cd nordlynx
chmod +x nordlynx-manager.sh
sudo ./nordlynx-manager.sh
```

یا تک‌خطی (خودش خودش را نصب می‌کند):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/sepehrwwe49/nordlynx/main/nordlynx-manager.sh)
```

وقتی از روی pipe اجرا شود، تشخیص می‌دهد که فایلی روی دیسک ندارد، هر دو فایل
(`nordlynx-manager.sh` و `nordlynx-bot.sh`) را در `/opt/nordlynx-manager/src/` دانلود
می‌کند، سینتکس هر دو را چک می‌کند، خودش را به `/usr/local/bin/nordlynx` لینک می‌کند و
دوباره اجرا می‌شود. از آن به بعد فقط کافی است بزنی:

```bash
sudo nordlynx
```

گزینه **۱۹** (یا `sudo nordlynx --update`) نسخه جدید را از گیت‌هاب می‌گیرد و اگر ربات
تلگرام نصب باشد آن را هم ری‌استارت می‌کند.

### زبان و نمایش درست فارسی

گزینه **۱۷** یک منوی انتخاب زبان باز می‌کند که از هر حالت یک **پیش‌نمایش زنده** نشان می‌دهد —
همان‌جا می‌بینی کدام روی ترمینال خودت درست رندر می‌شود و همان را انتخاب می‌کنی:

| حالت | توضیح |
|---|---|
| `English` | انگلیسی |
| `Русский` | روسی |
| `简体中文` | چینی ساده — نیاز به فونت CJK |
| **`Finglish`** | فارسی با حروف لاتین — **همه‌جا درست نمایش داده می‌شود**. حالت پیشنهادی |
| `فارسی` | pre-shaped (حروف چسبیده + ترتیب معکوس). بسته به فونت ترمینال ممکن است فاصله‌دار بیفتد |
| `فارسی (خام)` | ترتیب منطقی — فقط برای ترمینال‌هایی که خودشان bidi و shaping دارند |

**چرا؟** ترمینال متن را در یک شبکه‌ی سلولی می‌چیند و برای هر کاراکتر یک عرض ثابت فرض
می‌کند. الگوریتم دوجهته (bidi) و چسباندن حروف عربی را هم اجرا نمی‌کند. نتیجه: فارسی خام
برعکس و جدا-جدا، و فارسی pre-shaped بسته به فونت ممکن است فاصله‌دار دیده شود. این محدودیت
ترمینال و فونت است، نه اسکریپت — به همین دلیل حالت **Finglish** اضافه شد که هیچ‌وقت خراب
نمی‌شود.

### مسیر پیشنهادی بار اول

| گزینه | کار |
|---|---|
| ۱ | نصب پیش‌نیازها (داکر، tun، curl، jq) |
| ۲ | ثبت اکسس‌توکن‌ها — چند توکن با اسم دلخواه، حذف و نمایش |
| ۳ | ساخت ایمیج (چند دقیقه، فقط یک‌بار) |
| ۵ | ساخت سریع ۵ لوکیشن: آمریکا، ترکیه، امارات، استرالیا، هلند |
| ۸ | تست همه پروکسی‌ها و دیدن آی‌پی و کشور واقعی هرکدام |
| ۱۲ | گرفتن خروجی اوتباند برای مرزبان / پاسارگارد |

### امکانات

- منوی گرافیکی کاملاً عددی، رنگی، با اسپینر و پروگرس‌بار — بدون هیچ وابستگی، حتی روی SSH خام
- شش حالت زبان: انگلیسی، روسی، چینی، Finglish، فارسی (pre-shaped) و فارسی خام
- انتخاب پروتکل اتصال برای هر لوکیشن: **NordLynx** یا **OpenVPN**
- برای OpenVPN انتخاب **UDP / TCP**
- روشن و خاموش کردن **Auto-connect**، **LAN discovery** و **Analytics** برای هر کانتینر
- تغییر **پورت SOCKS** هاست و پورت داخلی کانتینر
- ساخت خودکار `Dockerfile` و `entrypoint.sh` و build ایمیج
- ۳۰ کشور آماده با پرچم + امکان وارد کردن کشور دلخواه
- تغییر کشور یا هر تنظیم دیگر با **حفظ همان نام و همان پورت هاست**
- **ابزار WireGuard**: نمایش کلید خصوصی، ساخت فایل `.conf` و QR از لوکیشن انتخاب‌شده
- داشبورد وضعیت زنده + تست آی‌پی خروجی واقعی
- خروجی آماده اوتباند و Routing برای Xray
- ترمیم خودکار: کران هر ۵ دقیقه پروکسی خراب را ری‌استارت می‌کند
- بکاپ و بازگردانی همه لوکیشن‌ها روی سرور جدید

### ربات تلگرام (گزینه ۱۷)

توکن ربات را از [@BotFather](https://t.me/BotFather) بگیر، آیدی عددی خودت را از
[@userinfobot](https://t.me/userinfobot) بردار و به‌عنوان ادمین اضافه کن (چند ادمین
پشتیبانی می‌شود). بعد گزینه ۴ ربات را به‌صورت سرویس systemd نصب و اجرا می‌کند.

داخل ربات:

- **🔑 اکسس‌توکن‌ها** — لیست با مقدار ماسک‌شده و تعداد لوکیشن هر توکن، افزودن (اسم + توکن)، حذف
- **➕ ساخت لوکیشن** — چهار مرحله: انتخاب توکن ← انتخاب کشور ← انتخاب شهر (از خود نورد خوانده
  می‌شود) ← انتخاب پورت از پیشنهادها یا تایپ دستی. بعد می‌سازد و آی‌پی خروجی واقعی را می‌فرستد.
- **📋 لیست لوکیشن‌ها** — با کلیک روی هر لوکیشن: توکن فعال، آپ‌تایم، وضعیت اتصال نورد، کشور و
  شهر و سرور متصل‌شده. دکمه‌ها: **تغییر پورت**، **خروجی اوتباند socks**، **تغییر لوکیشن**.

تغییر پورت یا تغییر لوکیشن، کانتینر را با **همان نام** بازمی‌سازد و در پایان به منوی اصلی
برمی‌گردد (بدون دکمه بازگشت اضافه).

فقط آیدی‌های ادمین دسترسی دارند؛ بقیه فقط آیدی خودشان را می‌بینند. چون توکن در چت وارد
می‌شود، بعد از ارسال پیامِ حاوی توکن آن را پاک کن — تلگرام تاریخچه را نگه می‌دارد.

### هشدار درباره کلید WireGuard

کلید خصوصی WireGuard یک **credential کامل** است — هرکس آن را داشته باشد می‌تواند از
اشتراک نورد تو استفاده کند. فایل‌های `.conf` را در گیت نگذار و بعد از نمایش QR صفحه را پاک کن.

### نکته مهم درباره پورت

داخل همه کانتینرها microsocks روی `1080` است؛ روی هاست هر لوکیشن پورت جداگانه دارد:

```
۱۰۸۱ آمریکا · ۱۰۸۲ ترکیه · ۱۰۸۳ امارات · ۱۰۸۴ استرالیا · ۱۰۸۵ هلند
```

هنگام تغییر کشور، پورت هاست حفظ می‌شود تا تنظیمات مرزبان دست‌نخورده بماند.

### هشدار امنیتی

اکسس‌توکن نورد یک credential حساس است. آن را در گیت، چت یا فایل عمومی قرار نده.
اگر جایی منتشر شد، در پنل Nord Account باطلش کن و توکن جدید بساز.
همچنین bind پیش‌فرض `127.0.0.1` است؛ اگر روی `0.0.0.0` بگذاری یک پروکسی SOCKS5 **باز و بدون
احراز هویت** روی اینترنت منتشر کرده‌ای — حتماً فایروال بگذار.

### رفع اشکال

| مشکل | راه‌حل |
|---|---|
| خطای `nordvpnd.sock` | کانتینر به `--cap-add=NET_ADMIN` و `/dev/net/tun` نیاز دارد — گزینه ۱ را دوباره بزن |
| Login failed | توکن منقضی یا اشتباه است — توکن جدید بساز، گزینه ۲، بعد کانتینرها را دوباره بساز |
| روی Disconnected می‌ماند | نام کشور باید دقیقاً با فرمت نورد باشد: `United_Arab_Emirates` |
| آی‌پی کشور اشتباه | همان لوکیشن را با گزینه ۶ دوباره بساز |
| Port already in use | `ss -lntp \| grep :1085` و کانتینر قدیمی را حذف کن |

</div>

---

<div align="center">

**MIT © [sepehrwwe49](https://github.com/sepehrwwe49)** · not affiliated with NordVPN

اگر به کارت آمد، یک ⭐ بده.

</div>
