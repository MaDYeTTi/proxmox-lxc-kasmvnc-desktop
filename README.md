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
- Firefox ESR
- persistent `desktop` user/profile

Docker and LXC nesting are not required.

## Features

- Firefox ESR, Chromium, both, or no browser
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
| `var_browser` | `firefox` | `firefox`, `chromium`, `both`, `none` |
| `var_auth_mode` | `kasm` | `kasm` or `external` |
| `var_desktop_user` | `desktop` | Linux desktop account |
| `var_kasm_user` | `desktop` | KasmVNC login name |
| `var_kasm_password` | generated | KasmVNC password in `kasm` mode |
| `var_extra_packages` | empty | whitespace-separated Debian packages |
| `var_web_port` | `8443` | KasmVNC web port |
| `var_listen_address` | `0.0.0.0` | KasmVNC listen address |
| `var_bind_mounts` | empty | optional host bind mounts |

Example for Chromium plus a few desktop tools:

```bash
export COMMUNITY_SCRIPTS_URL="https://raw.githubusercontent.com/MaDYeTTi/proxmox-lxc-kasmvnc-desktop/feat/initial-bootstrap"
export var_browser="chromium"
export var_extra_packages="thunar mousepad"

bash -c "$(curl -fsSL "$COMMUNITY_SCRIPTS_URL/ct/kasmvnc-desktop.sh")"
```

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
