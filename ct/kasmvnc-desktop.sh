#!/usr/bin/env bash

# Copyright (c) 2026 Yury Ershov
# License: MIT
# Source: https://github.com/kasmtech/KasmVNC
# Project: https://github.com/MaDYeTTi/proxmox-lxc-kasmvnc-desktop

# Until this project is moved into community-scripts/ProxmoxVED, tell the
# Community Scripts engine where this repository's install/ tree lives.
export COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/MaDYeTTi/proxmox-lxc-kasmvnc-desktop/main}"

_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
# shellcheck disable=SC1090
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

APP="KasmVNC Desktop"
var_tags="${var_tags:-desktop;remote-access}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-16}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_nesting="${var_nesting:-1}"

# Application-specific variables. These are deliberately environment-driven so
# they can later map directly to Community Scripts app_vars.
export var_browser="${var_browser:-falkon}"
export var_auth_mode="${var_auth_mode:-kasm}"
export var_desktop_user="${var_desktop_user:-desktop}"
export var_kasm_user="${var_kasm_user:-desktop}"
export var_kasm_password="${var_kasm_password:-}"
export var_extra_packages="${var_extra_packages:-}"
export var_web_port="${var_web_port:-8443}"
export var_listen_address="${var_listen_address:-0.0.0.0}"
export var_tls_mode="${var_tls_mode:-selfsigned}"
export var_tls_hostname="${var_tls_hostname:-}"
export var_tls_email="${var_tls_email:-}"
export var_acme_challenge="${var_acme_challenge:-http}"
export var_duckdns_domain="${var_duckdns_domain:-}"
export var_duckdns_token="${var_duckdns_token:-}"
export var_duckdns_update_ip="${var_duckdns_update_ip:-false}"
export var_bind_mounts="${var_bind_mounts:-}"

header_info "$APP"
variables
# APP contains a space; keep the public/application slug hyphenated.
NSAPP="kasmvnc-desktop"
export var_install="${NSAPP}-install"
color
catch_errors

update_kasmvnc() {
  ensure_dependencies curl jq

  local release_json release arch asset_name asset_url current tmp_deb
  release_json="$(curl -fsSL https://api.github.com/repos/kasmtech/KasmVNC/releases/latest)"
  release="$(jq -r '.tag_name | ltrimstr("v")' <<<"$release_json")"
  arch="$(dpkg --print-architecture)"
  asset_name="kasmvncserver_trixie_${release}_${arch}.deb"
  asset_url="$(jq -r --arg name "$asset_name" '.assets[] | select(.name == $name) | .browser_download_url' <<<"$release_json")"

  if [[ -z "$release" || "$release" == "null" || -z "$asset_url" || "$asset_url" == "null" ]]; then
    msg_error "Unable to resolve the latest KasmVNC package for Debian 13/${arch}."
    return 1
  fi

  current="$(dpkg-query -W -f='${Version}' kasmvncserver 2>/dev/null || true)"
  if [[ -n "$current" ]] && dpkg --compare-versions "$current" ge "$release"; then
    msg_ok "KasmVNC is already current (${current})."
    return 0
  fi

  msg_info "Updating KasmVNC to v${release}"
  tmp_deb="$(mktemp --suffix=.deb)"
  curl -fsSL "$asset_url" -o "$tmp_deb"
  apt-get install -y "$tmp_deb"
  rm -f "$tmp_deb"
  systemctl restart kasmvnc-desktop.service
  msg_ok "Updated KasmVNC to v${release}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /etc/systemd/system/kasmvnc-desktop.service ]]; then
    msg_error "No ${APP} installation found!"
    exit 1
  fi

  msg_info "Refreshing Debian package metadata"
  apt-get update -y
  msg_ok "Refreshed Debian package metadata"

  local browser_packages=()
  dpkg-query -W falkon >/dev/null 2>&1 && browser_packages+=(falkon)
  dpkg-query -W firefox-esr >/dev/null 2>&1 && browser_packages+=(firefox-esr)
  dpkg-query -W chromium >/dev/null 2>&1 && browser_packages+=(chromium)
  if ((${#browser_packages[@]} > 0)); then
    msg_info "Updating installed browser packages"
    apt-get install -y --only-upgrade "${browser_packages[@]}"
    msg_ok "Updated installed browser packages"
  fi

  update_kasmvnc
  msg_ok "Updated successfully!"
  exit
}

validate_bind_mount_entry() {
  local entry="$1"
  local host_path container_path mode extra

  IFS=':' read -r host_path container_path mode extra <<<"$entry"

  [[ -z "$extra" ]] || {
    msg_error "Invalid bind mount '${entry}': ':' is reserved as a field separator."
    return 1
  }
  [[ "$host_path" == /* && "$host_path" != "/" ]] || {
    msg_error "Invalid host path in bind mount '${entry}'."
    return 1
  }
  [[ "$container_path" == /* && "$container_path" != "/" ]] || {
    msg_error "Invalid container path in bind mount '${entry}'."
    return 1
  }
  [[ "$mode" == "ro" || "$mode" == "rw" ]] || {
    msg_error "Bind mount mode must be ro or rw in '${entry}'."
    return 1
  }
  [[ "$host_path" != *","* && "$container_path" != *","* ]] || {
    msg_error "Comma characters are not supported in bind mount paths."
    return 1
  }
  [[ -e "$host_path" ]] || {
    msg_error "Bind mount source does not exist on the Proxmox host: ${host_path}"
    return 1
  }
}

next_mount_index() {
  local i=0
  while pct config "$CTID" | grep -q "^mp${i}:"; do
    ((i += 1))
  done
  echo "$i"
}

apply_bind_mounts() {
  [[ -n "${var_bind_mounts:-}" ]] || return 0

  local entries entry host_path container_path mode extra idx spec
  local was_running=0

  IFS=';' read -r -a entries <<<"$var_bind_mounts"

  for entry in "${entries[@]}"; do
    [[ -n "$entry" ]] || continue
    validate_bind_mount_entry "$entry"
  done

  if pct status "$CTID" | grep -q "status: running"; then
    was_running=1
    msg_info "Stopping container to apply bind mounts"
    pct stop "$CTID"
    msg_ok "Stopped container"
  fi

  for entry in "${entries[@]}"; do
    [[ -n "$entry" ]] || continue
    IFS=':' read -r host_path container_path mode extra <<<"$entry"
    idx="$(next_mount_index)"
    spec="${host_path},mp=${container_path}"
    [[ "$mode" == "ro" ]] && spec+=",ro=1"

    msg_info "Adding bind mount mp${idx}: ${host_path} -> ${container_path} (${mode})"
    pct set "$CTID" "-mp${idx}" "$spec"
    msg_ok "Added bind mount mp${idx}"
  done

  if ((was_running)); then
    msg_info "Starting container"
    pct start "$CTID"
    msg_ok "Started container"
  fi

  msg_warn "Bind-mount ownership was not changed. Check UID/GID mapping for this unprivileged LXC."
}

start
build_container
apply_bind_mounts
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
if [[ "$var_tls_mode" == "letsencrypt" ]]; then
  echo -e "${INFO}${YW}Access KasmVNC at: ${BGN}https://${var_tls_hostname}:${var_web_port}${CL}"
else
  echo -e "${INFO}${YW}Access KasmVNC at: ${BGN}https://${IP}:${var_web_port}${CL}"
fi
if [[ "$var_auth_mode" == "external" ]]; then
  echo -e "${INFO}${YW}Authentication mode: external/none. Do not expose the KasmVNC backend directly.${CL}"
fi
