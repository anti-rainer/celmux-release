#!/bin/sh
set -eu

APP_NAME="celmux"
SERVICE_NAME="celmux"
INSTALL_ROOT="/opt/${APP_NAME}"
INSTALL_BIN="${INSTALL_ROOT}/bin/${APP_NAME}"
CONFIG_DIR="${INSTALL_ROOT}/config"
WORK_DIR="${INSTALL_ROOT}"
INIT_SYSTEM=""
SERVICE_FILE=""
SERVICE_DROPIN_DIR="/etc/systemd/system/${SERVICE_NAME}.service.d"

usage() {
	cat <<EOF
Usage:
  sh uninstall.sh

This removes all celmux-owned files:
  Binary:          ${INSTALL_BIN}
  Config dir:      ${CONFIG_DIR}
  Working dir:     ${WORK_DIR}
  Service:         systemd on Debian, procd on OpenWrt
EOF
}

die() {
	echo "error: $*" >&2
	exit 1
}

require_root() {
	if [ "$(id -u)" -ne 0 ]; then
		die "please run as root, for example: sudo sh scripts/uninstall.sh"
	fi
}

detect_init_system() {
	if [ -f /etc/openwrt_release ]; then
		[ -x /etc/rc.common ] || die "OpenWrt rc.common was not found"
		INIT_SYSTEM="procd"
		SERVICE_FILE="/etc/init.d/${SERVICE_NAME}"
		return
	fi
	if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
		INIT_SYSTEM="systemd"
		SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
		return
	fi
	die "unsupported init system: celmux requires systemd or OpenWrt procd"
}

systemctl_quiet() {
	systemctl "$@" >/dev/null 2>&1 || true
}

stop_services() {
	if [ "$INIT_SYSTEM" = "procd" ]; then
		if [ -x "$SERVICE_FILE" ]; then
			"$SERVICE_FILE" stop >/dev/null 2>&1 || true
			"$SERVICE_FILE" disable >/dev/null 2>&1 || true
		fi
	else
		systemctl_quiet stop "${SERVICE_NAME}.service"
		systemctl_quiet disable "${SERVICE_NAME}.service"
		systemctl_quiet reset-failed "${SERVICE_NAME}.service"
	fi
}

remove_paths() {
	rm -rf "$INSTALL_ROOT"
	rm -f "$SERVICE_FILE"
	rm -rf "$SERVICE_DROPIN_DIR"
}

reload_system() {
	if [ "$INIT_SYSTEM" = "systemd" ]; then
		systemctl_quiet daemon-reload
	fi
}

main() {
	if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
		usage
		exit 0
	fi
	[ $# -eq 0 ] || die "unknown argument: $1"

	require_root
	detect_init_system
	stop_services
	remove_paths
	reload_system

	echo "celmux uninstalled."
}

main "$@"
