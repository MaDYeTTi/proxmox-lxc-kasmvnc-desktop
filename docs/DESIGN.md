# KasmVNC Desktop — design

## Goal

Provide a lightweight, persistent Linux desktop in an **unprivileged Proxmox LXC**
that is accessed from a normal web browser through KasmVNC.

The project is deliberately structured so that it can later be contributed to
the Proxmox Community Scripts project with minimal rework.

## Baseline

- Debian 13 (Trixie)
- unprivileged LXC
- 2 vCPU
- 2 GiB RAM
- 16 GiB root disk
- KasmVNC
- Openbox
- persistent desktop user and profile
- Falkon by default

No Docker and no nested container runtime are required.

## Application choices

`var_browser`:

- `falkon` — Falkon (default; lightweight Qt WebEngine browser)
- `firefox` — Firefox ESR
- `chromium` — Chromium
- `both` — Firefox ESR and Chromium
- `all` — Falkon, Firefox ESR and Chromium
- `none` — no browser; useful with `var_extra_packages`

Additional Debian packages may be installed with `var_extra_packages`.
Input is treated as a whitespace-separated list of Debian package names and is
validated before being passed to APT. It is not a shell command hook.

## TLS certificate modes

`var_tls_mode`:

- `selfsigned` — default KasmVNC/Debian certificate behavior; preferred behind
  a reverse proxy
- `letsencrypt` — direct-access mode using Certbot

`var_acme_challenge` selects certificate validation:

- `http` — standalone HTTP-01; public DNS and inbound TCP/80 must reach the LXC
- `duckdns` — DNS-01 using DuckDNS' TXT update API; no inbound validation port
  is required

DuckDNS DNS-01 requires `var_duckdns_domain` and `var_duckdns_token`.
`var_duckdns_update_ip=true` additionally installs a systemd timer that updates
the DuckDNS IPv4 record every five minutes. DDNS and ACME validation are
separate features and can be enabled independently.

Let's Encrypt mode requires `var_tls_hostname` and `var_tls_email`. Certbot's
deploy hook copies renewed material into a service-specific directory readable
through the `ssl-cert` group, then restarts KasmVNC.

TLS and application authentication are independent. A direct Internet-facing
Let's Encrypt deployment should normally keep `var_auth_mode=kasm`.

## Authentication

`var_auth_mode`:

- `kasm` — KasmVNC HTTP authentication (default)
- `external` — KasmVNC authentication disabled; intended only when access is
  protected externally, for example by Caddy with client-certificate mTLS

External authentication mode is intentionally explicit. Anyone who can connect
directly to the KasmVNC listening port can access the desktop. The deployment
owner is responsible for preventing direct access around the authenticating
reverse proxy.

For an mTLS deployment the intended path is:

```text
client browser -- HTTPS + mTLS --> Caddy -- reverse proxy --> KasmVNC LXC
```

mTLS terminates at Caddy. KasmVNC itself does not perform mTLS authentication.

## Bind mounts

`var_bind_mounts` is a host-side feature and therefore belongs in
`ct/kasmvnc-desktop.sh`, not the in-container installer.

Syntax:

```text
/host/path:/container/path:rw;/other/host/path:/container/path:ro
```

Rules:

- source path must already exist on the Proxmox host
- container path must be absolute
- mode is `ro` or `rw`
- existing host ownership is never changed automatically
- multiple mounts are assigned to the next available `mpN`
- bind mounts are applied after the application installation and the CT is
  restarted if required

For unprivileged containers, UID/GID mapping remains the administrator's
responsibility. The script must never recursively `chown` an existing host
directory.

## Separation of responsibilities

### `ct/kasmvnc-desktop.sh`

Runs on the Proxmox host and owns:

- Community Scripts container creation
- LXC defaults
- application variable export
- host bind mounts
- update entry point

### `install/kasmvnc-desktop-install.sh`

Runs inside the LXC and owns:

- dependency installation
- KasmVNC installation
- desktop user creation
- Openbox/session configuration
- optional browser/package installation
- KasmVNC authentication mode
- systemd service

## Community Scripts target

The eventual upstream target is the standard two-file layout:

```text
ct/kasmvnc-desktop.sh
install/kasmvnc-desktop-install.sh
```

New applications are expected to be tested through the Community Scripts
ProxmoxVED repository before promotion to ProxmoxVE.

## Security principles

- unprivileged LXC by default
- no nesting unless a future feature proves it necessary
- browser runs as a non-root user
- external/no-auth mode is opt-in
- arbitrary shell execution is not accepted as an installer option
- bind-mount ownership is not silently modified
- direct access to an unauthenticated backend should be restricted by firewall
  or network policy when an authenticating reverse proxy is used
