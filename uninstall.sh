#!/bin/sh
# Celmux uninstaller. Copyright 2026 anti-rainer.
# Usage: curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/anti-rainer/celmux-release/main/uninstall.sh | sudo bash
set -eu

APP_NAME="celmux"
SERVICE_NAME="celmux"
INSTALL_ROOT="${CELMUX_INSTALL_ROOT:-/opt/celmux}"
PURGE=0
ASSUME_YES=0
INIT_SYSTEM=""
SERVICE_FILE=""

usage() {
	cat <<EOF
Usage:
  sh uninstall.sh [--purge] [--yes]

Without --purge, the service and binary are removed while config/data/logs stay.
--purge removes the complete ${INSTALL_ROOT} directory and requires --yes when non-interactive.
EOF
}

die() {
	echo "error: $*" >&2
	exit 1
}

validate_install_root() {
	case "$INSTALL_ROOT" in
		/opt|/opt/|""|*..*|*[!A-Za-z0-9_./-]*)
			die "CELMUX_INSTALL_ROOT must be a clean path below /opt"
			;;
		/opt/*) ;;
		*) die "CELMUX_INSTALL_ROOT must be below /opt" ;;
	esac
}

is_openwrt() {
	[ -f /etc/openwrt_release ] || [ -f /etc/openwrt_version ] ||
		{ [ -x /sbin/procd ] && [ -f /lib/functions/procd.sh ]; }
}

parse_args() {
	while [ "$#" -gt 0 ]; do
		case "$1" in
			-h|--help)
				usage
				exit 0
				;;
			--purge)
				PURGE=1
				;;
			--yes|-y)
				ASSUME_YES=1
				;;
			*) die "unknown argument: $1" ;;
		esac
		shift
	done
}

require_root() {
	[ "$(id -u)" -eq 0 ] || die "please run this uninstaller as root, for example: curl ... | sudo bash -s -- --purge --yes"
}

detect_init_system() {
	if { [ -f /system/build.prop ] || [ -d /data/adb ]; } && [ -f "/data/adb/service.d/${SERVICE_NAME}.sh" ]; then
		INIT_SYSTEM=android
		SERVICE_FILE="/data/adb/service.d/${SERVICE_NAME}.sh"
		return
	fi
	if command -v systemctl >/dev/null 2>&1 && [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
		INIT_SYSTEM=systemd
		SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
		return
	fi
	if is_openwrt && [ -x "/etc/init.d/${SERVICE_NAME}" ]; then
		INIT_SYSTEM=procd
		SERVICE_FILE="/etc/init.d/${SERVICE_NAME}"
		return
	fi
	if command -v rc-service >/dev/null 2>&1 && [ -x "/etc/init.d/${SERVICE_NAME}" ]; then
		INIT_SYSTEM=openrc
		SERVICE_FILE="/etc/init.d/${SERVICE_NAME}"
		return
	fi
	if [ -x "/etc/init.d/${SERVICE_NAME}" ]; then
		INIT_SYSTEM=sysvinit
		SERVICE_FILE="/etc/init.d/${SERVICE_NAME}"
		return
	fi
	INIT_SYSTEM=none
	SERVICE_FILE=""
}

systemctl_quiet() {
	systemctl "$@" >/dev/null 2>&1 || true
}

stop_service() {
	case "$INIT_SYSTEM" in
		android)
			"$SERVICE_FILE" stop >/dev/null 2>&1 || true
			;;
		procd)
			"$SERVICE_FILE" stop >/dev/null 2>&1 || true
			"$SERVICE_FILE" disable >/dev/null 2>&1 || true
			;;
		systemd)
			systemctl_quiet stop "${SERVICE_NAME}.service"
			systemctl_quiet disable "${SERVICE_NAME}.service"
			systemctl_quiet reset-failed "${SERVICE_NAME}.service"
			;;
		openrc)
			rc-service "$SERVICE_NAME" stop >/dev/null 2>&1 || true
			rc-update del "$SERVICE_NAME" default >/dev/null 2>&1 || true
			;;
		sysvinit)
			"$SERVICE_FILE" stop >/dev/null 2>&1 || true
			if command -v update-rc.d >/dev/null 2>&1; then
				update-rc.d -f "$SERVICE_NAME" remove >/dev/null 2>&1 || true
			elif command -v chkconfig >/dev/null 2>&1; then
				chkconfig --del "$SERVICE_NAME" >/dev/null 2>&1 || true
			fi
			;;
	esac
}

remove_service() {
	[ -z "$SERVICE_FILE" ] || rm -f "$SERVICE_FILE"
	if [ "$INIT_SYSTEM" = systemd ]; then
		systemctl_quiet daemon-reload
	fi
}

confirm_purge() {
	[ "$PURGE" -eq 1 ] || return 0
	if [ "$ASSUME_YES" -eq 1 ]; then
		return 0
	fi
	if [ ! -t 0 ]; then
		die "--purge requires --yes when stdin is not interactive"
	fi
	printf 'Remove %s, including config and data? [y/N] ' "$INSTALL_ROOT"
	read -r answer || answer=""
	case "$answer" in
		y|Y|yes|YES) ;;
		*) die "purge cancelled" ;;
	esac
}

remove_files() {
	if [ "$PURGE" -eq 1 ]; then
		rm -rf "$INSTALL_ROOT"
		return
	fi
	rm -f "${INSTALL_ROOT}/bin/${APP_NAME}"
	rmdir "${INSTALL_ROOT}/bin" 2>/dev/null || true
}

main() {
	parse_args "$@"
	require_root
	validate_install_root
	detect_init_system
	confirm_purge
	stop_service
	remove_service
	remove_files
	if [ "$PURGE" -eq 1 ]; then
		echo "celmux removed, including ${INSTALL_ROOT}"
	else
		echo "celmux service and binary removed; config/data/logs were preserved under ${INSTALL_ROOT}"
	fi
}

main "$@"
