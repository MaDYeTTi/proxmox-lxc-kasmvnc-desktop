# Proxmox LXC KasmVNC Desktop

Lightweight, persistent Linux desktop for **Proxmox LXC**, accessed directly
from a modern web browser using [KasmVNC](https://github.com/kasmtech/KasmVNC).

The project is being developed with the intention of becoming a Proxmox
Community Scripts contribution.

> **Status:** early development. The initial bootstrap branch is intended for
> lab testing, not production deployment.

## What it builds

Default installation:

- Debian 13 (Trixie)
- unprivileged LXC
- 2 vCPU
- 2 GiB RAM
- 16 GiB root disk
- KasmVNC
- Openbox
- Falkon
- persistent `desktop` user/profile

Docker and LXC nesting are not required.

## Features

- Falkon, Firefox ESR, Chromium, multiple browsers, or no browser
- additional validated Debian packages
- KasmVNC username/password authentication
- optional external/no-auth mode for an authenticating reverse proxy
- optional Proxmox host bind mounts
- persistent browser/desktop profile
- dynamic desktop resizing and clipboard support provided by KasmVNC
- amd64 and arm64 package selection
- Community Scripts-compatible `ct/` + `install/` layout

See [docs/DESIGN.md](docs/DESIGN.md) for the architecture and security model.

## Development install

The current work is on `feat/initial-bootstrap`. Run this **from a Proxmox VE
host shell**:

```bash
export COMMUNITY_SCRIPTS_URL="https://raw.githubusercontent.com/MaDYeTTi/proxmox-lxc-kasmvnc-desktop/feat/initial-bootstrap"

bash -c "$(curl -fsSL "$COMMUNITY_SCRIPTS_URL/ct/kasmvnc-desktop.sh")"
```

The Community Scripts engine still provides the normal Default / Advanced LXC
configuration UI for storage, networking, CT ID, CPU, RAM, and related Proxmox
settings.

## Application variables

Application-specific settings can currently be supplied as environment
variables. They are designed to map to Community Scripts `app_vars` later.

| Variable | Default | Values / meaning |
| --- | --- | --- |
| `var_browser` | `falkon` | `falkon`, `firefox`, `chromium`, `both` (Firefox + Chromium), `all`, `none` |
| `var_auth_mode` | `kasm` | `kasm` or `external` |
| `var_desktop_user` | `desktop` | Linux desktop account |
| `var_kasm_user` | `desktop` | KasmVNC login name |
| `var_kasm_password` | generated | KasmVNC password in `kasm` mode |
| `var_extra_packages` | empty | whitespace-separated Debian packages |
| `var_web_port` | `8443` | KasmVNC web port |
| `var_listen_address` | `0.0.0.0` | KasmVNC listen address |
| `var_tls_mode` | `selfsigned` | `selfsigned` or `letsencrypt` |
| `var_tls_hostname` | empty | public FQDN for Let's Encrypt mode |
| `var_tls_email` | empty | ACME registration email for Let's Encrypt mode |
| `var_acme_challenge` | `http` | `http` or `duckdns` |
| `var_duckdns_domain` | empty | DuckDNS base subdomain, e.g. `myhost` |
| `var_duckdns_token` | empty | DuckDNS account token |
| `var_duckdns_update_ip` | `false` | periodically update the DuckDNS public IPv4 |
| `var_bind_mounts` | empty | optional host bind mounts |

Example for Chromium plus a few desktop tools:

```bash
export COMMUNITY_SCRIPTS_URL="https://raw.githubusercontent.com/MaDYeTTi/proxmox-lxc-kasmvnc-desktop/feat/initial-bootstrap"
export var_browser="chromium"
export var_extra_packages="thunar mousepad"

bash -c "$(curl -fsSL "$COMMUNITY_SCRIPTS_URL/ct/kasmvnc-desktop.sh")"
```

## Optional Let's Encrypt certificate

For direct-access deployments without a reverse proxy, KasmVNC can request and
renew a publicly trusted Let's Encrypt certificate.

Two ACME challenge modes are supported:

- `http` — Certbot standalone HTTP-01; inbound TCP/80 must reach the LXC
- `duckdns` — automated DNS-01 through the DuckDNS TXT API; no inbound port 80
  is required for certificate issuance or renewal

KasmVNC should normally keep its own authentication enabled for direct access.

Example:

```bash
export var_tls_mode="letsencrypt"
export var_tls_hostname="desktop.example.com"
export var_tls_email="admin@example.com"
export var_acme_challenge="http"
```

For DuckDNS DNS-01, for example `browser.myhost.duckdns.org`:

```bash
export var_tls_mode="letsencrypt"
export var_tls_hostname="browser.myhost.duckdns.org"
export var_tls_email="admin@example.com"
export var_acme_challenge="duckdns"
export var_duckdns_domain="myhost"
export var_duckdns_token="<duckdns-token>"
export var_duckdns_update_ip="true"
```

DuckDNS publishes the TXT value for its base subdomain and its sub-subdomains,
so the same DuckDNS base domain can validate a hostname below it. The optional
DDNS timer updates the base domain's public IPv4 every five minutes. The token
is stored root-only inside the LXC and is not written into the KasmVNC user
profile.

The certificate is requested with Certbot and copied to
`/etc/kasmvnc-desktop/tls/` with permissions readable by the KasmVNC service.
A Certbot deploy hook refreshes those files and restarts
`kasmvnc-desktop.service` after successful renewal.

The resulting direct URL is:

```text
https://desktop.example.com:8443
```

The default remains `selfsigned`, which is appropriate when TLS terminates at
a reverse proxy such as Caddy.

## External authentication / reverse proxy mode

For a deployment where authentication happens at a reverse proxy:

```bash
export COMMUNITY_SCRIPTS_URL="https://raw.githubusercontent.com/MaDYeTTi/proxmox-lxc-kasmvnc-desktop/feat/initial-bootstrap"
export var_auth_mode="external"
export var_browser="both"

bash -c "$(curl -fsSL "$COMMUNITY_SCRIPTS_URL/ct/kasmvnc-desktop.sh")"
```

The intended model is, for example:

```text
client browser -- HTTPS + mTLS --> Caddy -- reverse proxy --> KasmVNC LXC
```

In `external` mode KasmVNC's own web authentication is disabled. **Do not
allow untrusted clients to reach the KasmVNC backend directly.** Restrict the
backend port to the reverse proxy with Proxmox/network firewall policy.

mTLS in this design is between the client and Caddy; KasmVNC is not performing
client-certificate authentication.

## Bind mounts

Bind mounts are created on the Proxmox host after the CT/application build.

Syntax:

```text
/host/path:/container/path:rw;/other/path:/mnt/other:ro
```

Example:

```bash
export var_bind_mounts="/RUST/browser-share:/mnt/shared:rw"
```

The script intentionally does **not** change ownership of existing host paths.
For an unprivileged LXC, configure the source permissions/UID/GID mapping
appropriately.

## Generated credentials

When `var_auth_mode=kasm` and no password was supplied, a random password is
generated and stored inside the CT at:

```text
/root/kasmvnc-desktop-credentials
```

It can be read from the Proxmox host with:

```bash
pct exec <CTID> -- cat /root/kasmvnc-desktop-credentials
```

## License

MIT
