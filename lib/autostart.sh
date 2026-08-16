#!/usr/bin/env bash
# systemd --user unit rendering and idempotent installation.
# Sourced, never executed. Requires lib/common.sh.

coo_render_service_unit() {
  local exec_path=$1
  cat <<UNIT
[Unit]
Description=Cachy Omarchy Overlay Shell
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=$exec_path
Restart=on-failure
RestartSec=1

[Install]
WantedBy=default.target
UNIT
}

# Writes the unit only when its content would change.
# Return: 0 unchanged, 10 written or updated.
coo_install_service() {
  local dest_dir=$1 exec_path=$2
  local dest="$dest_dir/coo-shell.service"
  local rendered; rendered=$(coo_render_service_unit "$exec_path")

  mkdir -p "$dest_dir"
  if [[ -f $dest ]] && [[ $(cat "$dest") == "$rendered" ]]; then
    vlog "service unit unchanged: $dest"
    return 0
  fi
  printf '%s\n' "$rendered" > "$dest"
  vlog "service unit written: $dest"
  return 10
}
