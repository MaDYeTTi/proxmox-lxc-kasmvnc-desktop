#!/usr/bin/env bash

# Copyright (c) 2026 Yury Ershov
# License: MIT
# Source: https://github.com/kasmtech/KasmVNC
# Project: https://github.com/MaDYeTTi/proxmox-lxc-kasmvnc-desktop

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

var_browser="${var_browser:-firefox}"
var_auth_mode="${var_auth_mode:-kasm}"
var_desktop_user="${var_desktop_user:-desktop}"
var_kasm_user="${var_kasm_user:-desktop}"
var_kasm_password="${var_kasm_password:-}"
var_extra_packages="${var_extra_packages:-}"
var_web_port="${var_web_port:-8443}"
var_listen_address="${var_listen_address:-0.0.0.0}"

case "$var_browser" in
firefox | chromium | both | none) ;;
*)
  msg_error "Invalid var_browser '${var_browser}'. Use firefox, chromium, both, or none."
  exit 1
  ;;
esac

case "$var_auth_mode" in
kasm | external) ;;
*)
  msg_error "Invalid var_auth_mode '${var_auth_mode}'. Use kasm or external."
  exit 1
  ;;
esac

if [[ ! "$var_desktop_user" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
  msg_error "Invalid desktop username '${var_desktop_user}'."
  exit 1
fi

if [[ ! "$var_kasm_user" =~ ^[A-Za-z0-9_.@-]{1,64}$ ]]; then
  msg_error "Invalid KasmVNC username '${var_kasm_user}'."
  exit 1
fi

if [[ ! "$var_web_port" =~ ^[0-9]+$ ]] || ((var_web_port < 1 || var_web_port > 65535)); then
  msg_error "Invalid KasmVNC web port '${var_web_port}'."
  exit 1
fi

if [[ ! "$var_listen_address" =~ ^[A-Za-z0-9:._-]+$ ]]; then
  msg_error "Invalid listen address '${var_listen_address}'."
  exit 1
fi

msg_info "Installing desktop dependencies"
$STD apt-get install -y   ca-certificates   curl   jq   openssl   ssl-cert   dbus-x11   openbox   xterm   xdg-utils   fonts-dejavu-core   fonts-liberation
msg_ok "Installed desktop dependencies"

browser_packages=()
case "$var_browser" in
firefox)
  browser_packages+=(firefox-esr)
  ;;
chromium)
  browser_packages+=(chromium)
  ;;
both)
  browser_packages+=(firefox-esr chromium)
  ;;
none) ;;
esac

if ((${#browser_packages[@]} > 0)); then
  msg_info "Installing browser packages"
  $STD apt-get install -y "${browser_packages[@]}"
  msg_ok "Installed browser packages"
fi

extra_packages=()
if [[ -n "$var_extra_packages" ]]; then
  read -r -a requested_packages <<<"$var_extra_packages"

  for package in "${requested_packages[@]}"; do
    if [[ ! "$package" =~ ^[a-z0-9][a-z0-9+.-]*(:[a-z0-9]+)?$ ]]; then
      msg_error "Invalid Debian package name '${package}'."
      exit 1
    fi
    if ! apt-cache show "$package" >/dev/null 2>&1; then
      msg_error "Debian package '${package}' was not found."
      exit 1
    fi
    extra_packages+=("$package")
  done

  if ((${#extra_packages[@]} > 0)); then
    msg_info "Installing additional packages"
    $STD apt-get install -y "${extra_packages[@]}"
    msg_ok "Installed additional packages"
  fi
fi

msg_info "Installing KasmVNC"
release_json="$(curl -fsSL https://api.github.com/repos/kasmtech/KasmVNC/releases/latest)"
release="$(jq -r '.tag_name | ltrimstr("v")' <<<"$release_json")"
arch="$(dpkg --print-architecture)"
asset_name="kasmvncserver_trixie_${release}_${arch}.deb"
asset_url="$(jq -r --arg name "$asset_name" '.assets[] | select(.name == $name) | .browser_download_url' <<<"$release_json")"

if [[ -z "$release" || "$release" == "null" || -z "$asset_url" || "$asset_url" == "null" ]]; then
  msg_error "Unable to resolve a KasmVNC Debian 13 package for architecture '${arch}'."
  exit 1
fi

tmp_deb="$(mktemp --suffix=.deb)"
curl -fsSL "$asset_url" -o "$tmp_deb"
$STD apt-get install -y "$tmp_deb"
rm -f "$tmp_deb"
msg_ok "Installed KasmVNC v${release}"

msg_info "Creating desktop user"
if ! id "$var_desktop_user" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$var_desktop_user"
fi
usermod -a -G ssl-cert "$var_desktop_user"
desktop_home="$(getent passwd "$var_desktop_user" | cut -d: -f6)"
desktop_group="$(id -gn "$var_desktop_user")"
install -d -m 0700 -o "$var_desktop_user" -g "$desktop_group"   "$desktop_home/.vnc"   "$desktop_home/.config/openbox"   "$desktop_home/Downloads"
msg_ok "Created desktop user"

msg_info "Configuring Openbox session"
cat >"$desktop_home/.vnc/xstartup" <<'EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec dbus-run-session -- openbox-session
EOF
chmod 0755 "$desktop_home/.vnc/xstartup"

case "$var_browser" in
firefox | both)
  cat >"$desktop_home/.config/openbox/autostart" <<'EOF'
firefox-esr --new-instance &
EOF
  ;;
chromium)
  cat >"$desktop_home/.config/openbox/autostart" <<'EOF'
chromium --no-first-run --start-maximized &
EOF
  ;;
none)
  cat >"$desktop_home/.config/openbox/autostart" <<'EOF'
xterm &
EOF
  ;;
esac

chown -R "$var_desktop_user:$desktop_group"   "$desktop_home/.vnc"   "$desktop_home/.config"   "$desktop_home/Downloads"
msg_ok "Configured Openbox session"

msg_info "Configuring KasmVNC"
cat >"$desktop_home/.vnc/kasmvnc.yaml" <<EOF
desktop:
  resolution:
    width: 1920
    height: 1080
  allow_resize: true
  pixel_depth: 24

network:
  interface: ${var_listen_address}
  websocket_port: ${var_web_port}
  use_ipv4: true
  use_ipv6: true
  ssl:
    require_ssl: true

user_session:
  session_type: exclusive
  idle_timeout: never

command_line:
  prompt: false
EOF
chown "$var_desktop_user:$desktop_group" "$desktop_home/.vnc/kasmvnc.yaml"
chmod 0600 "$desktop_home/.vnc/kasmvnc.yaml"

if [[ "$var_auth_mode" == "kasm" ]]; then
  if [[ -z "$var_kasm_password" ]]; then
    var_kasm_password="$(openssl rand -base64 24 | tr -d '\n')"
    install -m 0600 /dev/null /root/kasmvnc-desktop-credentials
    {
      echo "username=${var_kasm_user}"
      echo "password=${var_kasm_password}"
    } >/root/kasmvnc-desktop-credentials
    credentials_generated=1
  fi

  printf '%s\n%s\n' "$var_kasm_password" "$var_kasm_password" |
    runuser -u "$var_desktop_user" -- env HOME="$desktop_home"       vncpasswd -u "$var_kasm_user" -w
else
  # vncserver with prompting disabled still expects its password database to
  # contain at least one entry. Create an unreachable internal account; web
  # BasicAuth is disabled by the service wrapper below.
  internal_password="$(openssl rand -base64 32 | tr -d '\n')"
  printf '%s\n%s\n' "$internal_password" "$internal_password" |
    runuser -u "$var_desktop_user" -- env HOME="$desktop_home"       vncpasswd -u internal -w
  unset internal_password
fi

chown "$var_desktop_user:$desktop_group" "$desktop_home/.kasmpasswd"
chmod 0600 "$desktop_home/.kasmpasswd"
msg_ok "Configured KasmVNC"

msg_info "Creating KasmVNC Desktop service"
install -d -m 0755 /etc/kasmvnc-desktop
cat >/etc/kasmvnc-desktop/config <<EOF
AUTH_MODE=${var_auth_mode}
DISPLAY_ID=:1
EOF
chmod 0644 /etc/kasmvnc-desktop/config

cat >/usr/local/sbin/kasmvnc-desktop-start <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

source /etc/kasmvnc-desktop/config

args=(-fg -prompt 0 "$DISPLAY_ID")

if [[ "$AUTH_MODE" == "external" ]]; then
  args+=(-disableBasicAuth -SecurityTypes None)
fi

exec /usr/bin/vncserver "${args[@]}"
EOF
chmod 0755 /usr/local/sbin/kasmvnc-desktop-start

cat >/etc/systemd/system/kasmvnc-desktop.service <<EOF
[Unit]
Description=KasmVNC Desktop
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=30
StartLimitBurst=5

[Service]
Type=simple
User=${var_desktop_user}
Group=${desktop_group}
SupplementaryGroups=ssl-cert
Environment=HOME=${desktop_home}
Environment=USER=${var_desktop_user}
Environment=LOGNAME=${var_desktop_user}
WorkingDirectory=${desktop_home}
ExecStartPre=-/usr/bin/vncserver -kill :1
ExecStart=/usr/local/sbin/kasmvnc-desktop-start
ExecStop=-/usr/bin/vncserver -kill :1
Restart=always
RestartSec=3
TimeoutStopSec=20

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable -q --now kasmvnc-desktop.service
msg_ok "Created KasmVNC Desktop service"

if [[ "$var_auth_mode" == "external" ]]; then
  msg_warn "KasmVNC authentication is disabled. Restrict direct access to port ${var_web_port} and protect the service with an authenticating reverse proxy or equivalent control."
elif [[ "${credentials_generated:-0}" == "1" ]]; then
  msg_warn "A KasmVNC password was generated. Retrieve it from /root/kasmvnc-desktop-credentials inside the container."
fi

motd_ssh
customize
cleanup_lxc
