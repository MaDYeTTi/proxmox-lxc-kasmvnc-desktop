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

var_browser="${var_browser:-falkon}"
var_auth_mode="${var_auth_mode:-kasm}"
var_desktop_user="${var_desktop_user:-desktop}"
var_kasm_user="${var_kasm_user:-desktop}"
var_kasm_password="${var_kasm_password:-}"
var_extra_packages="${var_extra_packages:-}"
var_web_port="${var_web_port:-8443}"
var_listen_address="${var_listen_address:-0.0.0.0}"
var_tls_mode="${var_tls_mode:-selfsigned}"
var_tls_hostname="${var_tls_hostname:-}"
var_tls_email="${var_tls_email:-}"
var_acme_challenge="${var_acme_challenge:-http}"
var_duckdns_domain="${var_duckdns_domain:-}"
var_duckdns_token="${var_duckdns_token:-}"
var_duckdns_update_ip="${var_duckdns_update_ip:-false}"

case "$var_browser" in
falkon | firefox | chromium | both | all | none) ;;
*)
  msg_error "Invalid var_browser '${var_browser}'. Use falkon, firefox, chromium, both, all, or none."
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

case "$var_tls_mode" in
selfsigned | letsencrypt) ;;
*)
  msg_error "Invalid var_tls_mode '${var_tls_mode}'. Use selfsigned or letsencrypt."
  exit 1
  ;;
esac

case "$var_acme_challenge" in
http | duckdns) ;;
*)
  msg_error "Invalid var_acme_challenge '${var_acme_challenge}'. Use http or duckdns."
  exit 1
  ;;
esac

case "$var_duckdns_update_ip" in
true | false) ;;
*)
  msg_error "Invalid var_duckdns_update_ip '${var_duckdns_update_ip}'. Use true or false."
  exit 1
  ;;
esac

if [[ "$var_tls_mode" == "letsencrypt" ]]; then
  if [[ ! "$var_tls_hostname" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]; then
    msg_error "A valid public FQDN is required for Let's Encrypt."
    exit 1
  fi
  if [[ ! "$var_tls_email" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]; then
    msg_error "A valid email address is required for Let's Encrypt."
    exit 1
  fi
fi

if [[ "$var_acme_challenge" == "duckdns" || "$var_duckdns_update_ip" == "true" ]]; then
  if [[ ! "$var_duckdns_domain" =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,62}$ ]]; then
    msg_error "A DuckDNS base subdomain is required, for example 'myhost' for myhost.duckdns.org."
    exit 1
  fi
  if [[ ! "$var_duckdns_token" =~ ^[A-Za-z0-9-]{20,128}$ ]]; then
    msg_error "A valid DuckDNS token is required."
    exit 1
  fi
fi

if [[ "$var_acme_challenge" == "duckdns" && "$var_tls_mode" != "letsencrypt" ]]; then
  msg_error "var_acme_challenge=duckdns requires var_tls_mode=letsencrypt."
  exit 1
fi

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

if [[ "$var_tls_mode" == "letsencrypt" ]]; then
  msg_info "Installing Certbot"
  $STD apt-get install -y certbot
  msg_ok "Installed Certbot"
fi

browser_packages=()
case "$var_browser" in
falkon)
  browser_packages+=(falkon)
  ;;
firefox)
  browser_packages+=(firefox-esr)
  ;;
chromium)
  browser_packages+=(chromium)
  ;;
both)
  browser_packages+=(firefox-esr chromium)
  ;;
all)
  browser_packages+=(falkon firefox-esr chromium)
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
if [[ -f /etc/xdg/openbox/rc.xml ]]; then
  cp /etc/xdg/openbox/rc.xml "$desktop_home/.config/openbox/rc.xml"
  sed -i '/<desktops>/,/<\/desktops>/ s#<number>[0-9][0-9]*</number>#<number>1</number>#' \
    "$desktop_home/.config/openbox/rc.xml"
fi

cat >"$desktop_home/.vnc/xstartup" <<'EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec dbus-run-session -- openbox-session
EOF
chmod 0755 "$desktop_home/.vnc/xstartup"

case "$var_browser" in
falkon)
  cat >"$desktop_home/.config/openbox/autostart" <<'EOF'
falkon &
EOF
  ;;
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
all)
  cat >"$desktop_home/.config/openbox/autostart" <<'EOF'
falkon &
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

if [[ "$var_acme_challenge" == "duckdns" || "$var_duckdns_update_ip" == "true" ]]; then
  install -d -m 0755 /etc/kasmvnc-desktop
  cat >/etc/kasmvnc-desktop/duckdns.conf <<EOF
DUCKDNS_DOMAIN='${var_duckdns_domain}'
DUCKDNS_TOKEN='${var_duckdns_token}'
EOF
  chmod 0600 /etc/kasmvnc-desktop/duckdns.conf
fi

if [[ "$var_duckdns_update_ip" == "true" ]]; then
  msg_info "Configuring DuckDNS dynamic DNS updates"
  cat >/usr/local/sbin/kasmvnc-duckdns-update <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source /etc/kasmvnc-desktop/duckdns.conf
export DUCKDNS_DOMAIN DUCKDNS_TOKEN

python3 <<'PY'
import os
import urllib.parse
import urllib.request

params = urllib.parse.urlencode({
    "domains": os.environ["DUCKDNS_DOMAIN"],
    "token": os.environ["DUCKDNS_TOKEN"],
})
with urllib.request.urlopen("https://www.duckdns.org/update?" + params, timeout=20) as response:
    result = response.read().decode().strip()
if result != "OK":
    raise SystemExit(f"DuckDNS update failed: {result}")
PY
EOF
  chmod 0755 /usr/local/sbin/kasmvnc-duckdns-update

  cat >/etc/systemd/system/kasmvnc-duckdns.service <<'EOF'
[Unit]
Description=Update DuckDNS address
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/kasmvnc-duckdns-update
EOF

  cat >/etc/systemd/system/kasmvnc-duckdns.timer <<'EOF'
[Unit]
Description=Periodically update DuckDNS address

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
RandomizedDelaySec=30
Persistent=true

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable -q --now kasmvnc-duckdns.timer
  /usr/local/sbin/kasmvnc-duckdns-update
  msg_ok "Configured DuckDNS dynamic DNS updates"
fi

if [[ "$var_tls_mode" == "letsencrypt" ]]; then
  msg_info "Requesting Let's Encrypt certificate for ${var_tls_hostname}"
  install -d -m 0750 -o root -g ssl-cert /etc/kasmvnc-desktop/tls
  install -d -m 0755 /etc/letsencrypt/renewal-hooks/deploy

  cat >/etc/letsencrypt/renewal-hooks/deploy/kasmvnc-desktop <<EOF
#!/usr/bin/env bash
set -euo pipefail

install -m 0640 -o root -g ssl-cert \
  "/etc/letsencrypt/live/${var_tls_hostname}/fullchain.pem" \
  /etc/kasmvnc-desktop/tls/fullchain.pem
install -m 0640 -o root -g ssl-cert \
  "/etc/letsencrypt/live/${var_tls_hostname}/privkey.pem" \
  /etc/kasmvnc-desktop/tls/privkey.pem

if systemctl -q is-enabled kasmvnc-desktop.service 2>/dev/null; then
  systemctl restart kasmvnc-desktop.service
fi
EOF
  chmod 0755 /etc/letsencrypt/renewal-hooks/deploy/kasmvnc-desktop

  if [[ "$var_acme_challenge" == "duckdns" ]]; then
    cat >/usr/local/sbin/kasmvnc-duckdns-acme-auth <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source /etc/kasmvnc-desktop/duckdns.conf
export DUCKDNS_DOMAIN DUCKDNS_TOKEN CERTBOT_VALIDATION

python3 <<'PY'
import os
import urllib.parse
import urllib.request

params = urllib.parse.urlencode({
    "domains": os.environ["DUCKDNS_DOMAIN"],
    "token": os.environ["DUCKDNS_TOKEN"],
    "txt": os.environ["CERTBOT_VALIDATION"],
})
with urllib.request.urlopen("https://www.duckdns.org/update?" + params, timeout=20) as response:
    result = response.read().decode().strip()
if result != "OK":
    raise SystemExit(f"DuckDNS TXT update failed: {result}")
PY

sleep 60
EOF
    chmod 0755 /usr/local/sbin/kasmvnc-duckdns-acme-auth

    cat >/usr/local/sbin/kasmvnc-duckdns-acme-cleanup <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source /etc/kasmvnc-desktop/duckdns.conf
export DUCKDNS_DOMAIN DUCKDNS_TOKEN

python3 <<'PY'
import os
import urllib.parse
import urllib.request

params = urllib.parse.urlencode({
    "domains": os.environ["DUCKDNS_DOMAIN"],
    "token": os.environ["DUCKDNS_TOKEN"],
    "clear": "true",
})
with urllib.request.urlopen("https://www.duckdns.org/update?" + params, timeout=20) as response:
    result = response.read().decode().strip()
if result != "OK":
    raise SystemExit(f"DuckDNS TXT cleanup failed: {result}")
PY
EOF
    chmod 0755 /usr/local/sbin/kasmvnc-duckdns-acme-cleanup

    certbot certonly \
      --manual \
      --preferred-challenges dns \
      --manual-auth-hook /usr/local/sbin/kasmvnc-duckdns-acme-auth \
      --manual-cleanup-hook /usr/local/sbin/kasmvnc-duckdns-acme-cleanup \
      --non-interactive \
      --agree-tos \
      --email "$var_tls_email" \
      --domain "$var_tls_hostname"
  else
    certbot certonly \
      --standalone \
      --non-interactive \
      --agree-tos \
      --preferred-challenges http-01 \
      --email "$var_tls_email" \
      --domain "$var_tls_hostname"
  fi

  /etc/letsencrypt/renewal-hooks/deploy/kasmvnc-desktop
  systemctl enable -q --now certbot.timer 2>/dev/null || true
  msg_ok "Installed Let's Encrypt certificate"
fi

msg_info "Configuring KasmVNC"
if [[ "$var_tls_mode" == "letsencrypt" ]]; then
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
    pem_certificate: /etc/kasmvnc-desktop/tls/fullchain.pem
    pem_key: /etc/kasmvnc-desktop/tls/privkey.pem
    require_ssl: true

user_session:
  session_type: exclusive
  idle_timeout: never

command_line:
  prompt: false
EOF
else
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
fi
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

if [[ "$var_tls_mode" == "letsencrypt" ]]; then
  msg_ok "Let's Encrypt certificate enabled for ${var_tls_hostname}"
fi

motd_ssh
customize
cleanup_lxc
