#!/bin/sh
set -eu
umask 077

APP_NAME="celmux"
SERVICE_NAME="celmux"
BIN_NAME="celmux"
INSTALL_ROOT="${CELMUX_INSTALL_ROOT:-/opt/${APP_NAME}}"
INSTALL_BIN="${INSTALL_ROOT}/bin/${BIN_NAME}"
CONFIG_DIR="${INSTALL_ROOT}/config"
CONFIG_FILE="${CONFIG_DIR}/config.yaml"
LEGAL_DIR="${INSTALL_ROOT}/share/licenses/${APP_NAME}"
WORK_DIR="${INSTALL_ROOT}"
DATABASE_FILE="${WORK_DIR}/data/celmux.db"
INIT_SYSTEM=""
SERVICE_FILE=""
MIGRATE_VOHIVE="${CELMUX_MIGRATE_VOHIVE:-ask}"
LEGACY_OPT_ROOT="${CELMUX_LEGACY_OPT_ROOT:-/opt/vohive}"
LEGACY_VAR_ROOT="${CELMUX_LEGACY_VAR_ROOT:-/var/lib/vohive}"
LEGACY_ETC_ROOT="${CELMUX_LEGACY_ETC_ROOT:-/etc/vohive}"
LEGACY_DB=""
LEGACY_CONFIG=""
BINARY_ARG=""
LEGAL_SOURCE_DIR="${CELMUX_LEGAL_SOURCE_DIR:-}"
LEGAL_SOURCE_EXPLICIT="${CELMUX_LEGAL_SOURCE_DIR:+yes}"

usage() {
	cat <<EOF
Usage:
  sh install-local.sh [path-to-celmux-binary]
      [--migrate-vohive | --no-migrate-vohive]

If no binary path is provided, the script auto-detects one from:
  ./dist/celmux_*_linux_<arch>

Installed paths:
  Binary:        ${INSTALL_BIN}
  Config file:   ${CONFIG_FILE}
  Working dir:   ${WORK_DIR}
  Data dir:      ${WORK_DIR}/data
  Log dir:       ${WORK_DIR}/logs
  Legal notices: ${LEGAL_DIR}
  Service:       systemd on Debian, procd on OpenWrt

When no celmux database exists and VoHive data is found, the installer asks
whether to migrate it. Set CELMUX_MIGRATE_VOHIVE=ask|yes|no for automation.
EOF
}

die() {
	echo "error: $*" >&2
	exit 1
}

require_root() {
	if [ "$(id -u)" -ne 0 ]; then
		die "please run this installer as root; sudo is optional and is not required on OpenWrt"
	fi
}

detect_init_system() {
	if [ -f /etc/openwrt_release ]; then
		[ -x /etc/rc.common ] || die "OpenWrt rc.common was not found"
		[ -d /etc/init.d ] || die "OpenWrt init directory was not found"
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

detect_arch() {
	case "$(uname -m)" in
		x86_64|amd64)
			echo "amd64"
			;;
		aarch64|arm64)
			echo "arm64"
			;;
		armv7l|armv7*|armv6l|armhf)
			die "armv7 releases are no longer produced; use an amd64 or arm64 host"
			;;
		*)
			die "unsupported architecture: $(uname -m)"
			;;
	esac
}

parse_args() {
	while [ $# -gt 0 ]; do
		case "$1" in
			-h|--help)
				usage
				exit 0
				;;
			--migrate-vohive)
				MIGRATE_VOHIVE=yes
				;;
			--no-migrate-vohive)
				MIGRATE_VOHIVE=no
				;;
			-*)
				die "unknown argument: $1"
				;;
			*)
				[ -z "$BINARY_ARG" ] || die "multiple binary paths provided"
				BINARY_ARG="$1"
				;;
		esac
		shift
	done
}

find_binary() {
	if [ -n "${1:-}" ]; then
		[ -f "$1" ] || die "binary not found: $1"
		echo "$1"
		return
	fi

	arch="$(detect_arch)"
	# shellcheck disable=SC2012,SC2086
	candidate="$(ls -t ../dist/${APP_NAME}_*_linux_${arch} ../dist/${APP_NAME}_linux_${arch} ./dist/${APP_NAME}_*_linux_${arch} ./dist/${APP_NAME}_linux_${arch} 2>/dev/null | head -n 1 || true)"
	[ -n "$candidate" ] || die "no binary found for linux/${arch}; run make build-${arch} first or pass a binary path"
	echo "$candidate"
}

copy_file_mode() {
	src="$1"
	dst="$2"
	mode="$3"
	if command -v install >/dev/null 2>&1; then
		install -m "$mode" "$src" "$dst"
	else
		cp "$src" "$dst"
		chmod "$mode" "$dst"
	fi
}

install_binary() {
	src="$1"
	mkdir -p "$(dirname "$INSTALL_BIN")"
	chmod 0750 "$(dirname "$INSTALL_BIN")"
	copy_file_mode "$src" "$INSTALL_BIN" 0750
}

detect_legal_source() {
	[ -n "$LEGAL_SOURCE_DIR" ] && return
	_script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P || true)"
	for _candidate in "$_script_dir" "$_script_dir/.."; do
		if [ -f "$_candidate/LICENSE" ] && [ -f "$_candidate/NOTICE.md" ]; then
			LEGAL_SOURCE_DIR="$_candidate"
			return
		fi
	done
}

install_legal_notices() {
	detect_legal_source
	if [ -z "$LEGAL_SOURCE_DIR" ]; then
		echo "warning: legal notice files were not found; binary installation continues" >&2
		return
	fi
	mkdir -p "$LEGAL_DIR"
	chmod 0755 "$LEGAL_DIR"
	for legal_file in LICENSE NOTICE.md THIRD_PARTY_NOTICES.md DISCLAIMER.md; do
		if [ ! -f "$LEGAL_SOURCE_DIR/$legal_file" ]; then
			if [ -n "$LEGAL_SOURCE_EXPLICIT" ]; then
				die "legal notice is missing: $LEGAL_SOURCE_DIR/$legal_file"
			fi
			echo "warning: legal notice is missing: $LEGAL_SOURCE_DIR/$legal_file" >&2
			continue
		fi
		copy_file_mode "$LEGAL_SOURCE_DIR/$legal_file" "$LEGAL_DIR/$legal_file" 0644
	done
}

detect_legacy_sources() {
	LEGACY_DB=""
	LEGACY_CONFIG=""
	for candidate in \
		"${LEGACY_OPT_ROOT}/data/vohive.db" \
		"${LEGACY_VAR_ROOT}/data/vohive.db"; do
		if [ -f "$candidate" ]; then
			LEGACY_DB="$candidate"
			break
		fi
	done
	for candidate in \
		"${LEGACY_OPT_ROOT}/config/config.yaml" \
		"${LEGACY_ETC_ROOT}/config.yaml"; do
		if [ -f "$candidate" ]; then
			LEGACY_CONFIG="$candidate"
			break
		fi
	done
}

normalize_migrate_mode() {
	case "$MIGRATE_VOHIVE" in
		1|yes|YES|true|TRUE|on|ON)
			MIGRATE_VOHIVE=yes
			;;
		0|no|NO|false|FALSE|off|OFF)
			MIGRATE_VOHIVE=no
			;;
		ask|ASK|"")
			MIGRATE_VOHIVE=ask
			;;
		*)
			die "CELMUX_MIGRATE_VOHIVE must be ask, yes, or no"
			;;
	esac
}

confirm_legacy_migration() {
	normalize_migrate_mode
	case "$MIGRATE_VOHIVE" in
		yes) return 0 ;;
		no) return 1 ;;
	esac

	if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
		echo "warning: VoHive data found but no interactive terminal is available; migration skipped" >&2
		echo "rerun with --migrate-vohive or CELMUX_MIGRATE_VOHIVE=yes to migrate" >&2
		return 1
	fi

	while :; do
		printf '发现旧 VoHive 数据，是否迁移到 celmux？ [Y/n] ' > /dev/tty || return 1
		answer=""
		IFS= read -r answer < /dev/tty || return 1
		case "$answer" in
			""|y|Y|yes|YES) return 0 ;;
			n|N|no|NO) return 1 ;;
			*) printf '请输入 y 或 n。\n' > /dev/tty ;;
		esac
	done
}

stop_legacy_service() {
	if [ "$INIT_SYSTEM" = "systemd" ]; then
		systemctl stop vohive.service >/dev/null 2>&1 || true
		systemctl disable vohive.service >/dev/null 2>&1 || true
	fi
	if [ -x /etc/init.d/vohive ]; then
		/etc/init.d/vohive stop >/dev/null 2>&1 || true
		if [ "$INIT_SYSTEM" = "procd" ]; then
			/etc/init.d/vohive disable >/dev/null 2>&1 || true
		elif command -v update-rc.d >/dev/null 2>&1; then
			update-rc.d vohive disable >/dev/null 2>&1 || true
		fi
	fi

	if command -v pidof >/dev/null 2>&1; then
		legacy_pids="$(pidof vohive 2>/dev/null || true)"
		if [ -n "$legacy_pids" ]; then
			for legacy_pid in $legacy_pids; do
				kill -TERM "$legacy_pid" 2>/dev/null || true
			done
			attempt=0
			while [ "$attempt" -lt 10 ] && pidof vohive >/dev/null 2>&1; do
				attempt=$((attempt + 1))
				sleep 1
			done
			legacy_pids="$(pidof vohive 2>/dev/null || true)"
			if [ -n "$legacy_pids" ]; then
				for legacy_pid in $legacy_pids; do
					kill -KILL "$legacy_pid" 2>/dev/null || true
				done
			fi
		fi
	fi
}

sqlite_quote() {
	printf '%s' "$1" | sed "s/'/''/g"
}

migrate_legacy_database() {
	[ -n "$LEGACY_DB" ] || return 0
	mkdir -p "$(dirname "$DATABASE_FILE")"
	tmp_db="${DATABASE_FILE}.migrate.$$"
	rm -f "$tmp_db" "${tmp_db}-wal" "${tmp_db}-shm"
	if command -v sqlite3 >/dev/null 2>&1; then
		escaped_tmp="$(sqlite_quote "$tmp_db")"
		if ! sqlite3 -cmd '.timeout 10000' "$LEGACY_DB" "VACUUM INTO '${escaped_tmp}';"; then
			rm -f "$tmp_db"
			return 1
		fi
		check="$(sqlite3 "$tmp_db" 'PRAGMA quick_check;' 2>/dev/null || true)"
		if [ "$check" != "ok" ]; then
			rm -f "$tmp_db"
			return 1
		fi
	else
		# OpenWrt does not ship sqlite3-cli by default. The legacy service is
		# stopped before this copy, so carrying the WAL sidecars preserves a
		# recoverable SQLite snapshot without adding a runtime dependency.
		if ! cp "$LEGACY_DB" "$tmp_db"; then
			rm -f "$tmp_db"
			return 1
		fi
		for suffix in -wal -shm; do
			if [ -f "${LEGACY_DB}${suffix}" ]; then
				cp "${LEGACY_DB}${suffix}" "${tmp_db}${suffix}" || {
					rm -f "$tmp_db" "${tmp_db}-wal" "${tmp_db}-shm"
					return 1
				}
			fi
		done
	fi
	chmod 0600 "$tmp_db" "${tmp_db}-wal" "${tmp_db}-shm" 2>/dev/null || true
	mv "$tmp_db" "$DATABASE_FILE"
	for suffix in -wal -shm; do
		if [ -f "${tmp_db}${suffix}" ]; then
			mv "${tmp_db}${suffix}" "${DATABASE_FILE}${suffix}"
		fi
	done
	echo "migrated VoHive database: $LEGACY_DB -> $DATABASE_FILE"
}

migrate_legacy_config() {
	[ -n "$LEGACY_CONFIG" ] || return 0
	mkdir -p "$CONFIG_DIR"
	tmp_config="${CONFIG_FILE}.migrate.$$"
	if ! copy_file_mode "$LEGACY_CONFIG" "$tmp_config" 0600; then
		rm -f "$tmp_config"
		return 1
	fi
	mv "$tmp_config" "$CONFIG_FILE"
	legacy_password_file="$(dirname "$LEGACY_CONFIG")/initial-admin-password"
	if [ -f "$legacy_password_file" ]; then
		copy_file_mode "$legacy_password_file" "$CONFIG_DIR/initial-admin-password" 0600
	else
		rm -f "$CONFIG_DIR/initial-admin-password"
	fi
	echo "migrated VoHive config: $LEGACY_CONFIG -> $CONFIG_FILE"
}

migrate_legacy_installation() {
	detect_legacy_sources
	if [ -e "$DATABASE_FILE" ] || { [ -z "$LEGACY_DB" ] && [ -z "$LEGACY_CONFIG" ]; }; then
		return
	fi

	echo "VoHive migration sources detected:"
	[ -z "$LEGACY_DB" ] || echo "  Database: $LEGACY_DB"
	[ -z "$LEGACY_CONFIG" ] || echo "  Config:   $LEGACY_CONFIG"

	if confirm_legacy_migration; then
		stop_legacy_service
		if ! migrate_legacy_database; then
			echo "warning: unable to migrate VoHive database; celmux will initialize an empty database" >&2
		fi
		if ! migrate_legacy_config; then
			echo "warning: unable to migrate VoHive config; celmux will use a blank config" >&2
		fi
	else
		stop_legacy_service
		echo "VoHive data migration skipped; celmux will use a blank installation."
	fi
}

write_default_config() {
	mkdir -p "$CONFIG_DIR"
	if [ -f "$CONFIG_FILE" ]; then
		echo "config exists, keep unchanged: $CONFIG_FILE"
		return
	fi

	initial_password="$(od -An -N18 -tx1 /dev/urandom | tr -d ' \n')"
	[ -n "$initial_password" ] || die "failed to generate initial admin password"
	cat > "$CONFIG_FILE" <<EOF
server:
  debug: false
  port: 7575

web:
  username: admin
  password: ${initial_password}

devices: []

vowifi:
  enabled: false

webhook:
  enabled: false
EOF
	chmod 0600 "$CONFIG_FILE"
	printf '%s\n' "$initial_password" > "$CONFIG_DIR/initial-admin-password"
	chmod 0600 "$CONFIG_DIR/initial-admin-password"
	echo "generated initial admin password: $CONFIG_DIR/initial-admin-password"
}

write_systemd_service() {
	cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=celmux modem management service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${WORK_DIR}
ExecStart=${INSTALL_BIN} -c ${CONFIG_FILE}
Restart=always
RestartSec=5s
Environment=CONFIG_PATH=${CONFIG_FILE}
Environment=HOME=${WORK_DIR}
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
ProtectKernelLogs=true
ProtectClock=true
ProtectHostname=true
LockPersonality=true
RestrictSUIDSGID=true
RestrictNamespaces=true
SystemCallArchitectures=native
ReadWritePaths=${WORK_DIR}
LimitCORE=0

[Install]
WantedBy=multi-user.target
EOF
	chmod 0644 "$SERVICE_FILE"
}

write_procd_service() {
	cat > "$SERVICE_FILE" <<EOF
#!/bin/sh /etc/rc.common

USE_PROCD=1
START=99
STOP=10

PROG="${INSTALL_BIN}"
CONFIG="${CONFIG_FILE}"
WORK_DIR="${WORK_DIR}"

start_service() {
	procd_open_instance
	procd_set_param command "\$PROG" -c "\$CONFIG"
	procd_set_param env "CONFIG_PATH=\$CONFIG" "HOME=\$WORK_DIR"
	procd_set_param cwd "\$WORK_DIR"
	procd_set_param respawn 3600 5 5
	procd_set_param stdout 1
	procd_set_param stderr 1
	procd_set_param file "\$CONFIG"
	procd_set_param limits core="0"
	procd_close_instance
}
EOF
	chmod 0755 "$SERVICE_FILE"
}

write_service() {
	case "$INIT_SYSTEM" in
		systemd) write_systemd_service ;;
		procd) write_procd_service ;;
		*) die "unsupported init system: $INIT_SYSTEM" ;;
	esac
}

start_service() {
	case "$INIT_SYSTEM" in
		systemd)
			systemctl daemon-reload
			systemctl enable "$SERVICE_NAME"
			systemctl restart "$SERVICE_NAME"
			;;
		procd)
			"$SERVICE_FILE" enable
			"$SERVICE_FILE" restart
			;;
	esac
}

main() {
	parse_args "$@"
	require_root
	detect_init_system
	binary_path="$(find_binary "$BINARY_ARG")"

	if [ "$INIT_SYSTEM" = "procd" ]; then
		echo "detected OpenWrt/procd"
	elif [ -f /etc/debian_version ]; then
		echo "detected Debian-compatible system"
	else
		echo "warning: /etc/debian_version not found; continuing anyway"
	fi

	mkdir -p "${WORK_DIR}/data" "${WORK_DIR}/logs" "${CONFIG_DIR}"
	chmod 0750 "${WORK_DIR}" "${WORK_DIR}/data" "${WORK_DIR}/logs" "${CONFIG_DIR}"
	install_binary "$binary_path"
	install_legal_notices
	migrate_legacy_installation
	# celmux replaces the legacy service even when the operator chooses a blank
	# installation or no readable legacy files remain.
	stop_legacy_service
	write_default_config
	write_service
	start_service

	echo
	echo "celmux installed."
	echo "Binary:      ${INSTALL_BIN}"
	echo "Config file: ${CONFIG_FILE}"
	echo "Work dir:    ${WORK_DIR}"
	echo "Legal files: ${LEGAL_DIR}"
	echo
	echo "Service:     ${SERVICE_FILE}"
	echo "Useful commands:"
	if [ "$INIT_SYSTEM" = "procd" ]; then
		echo "  /etc/init.d/${SERVICE_NAME} status"
		echo "  logread -e ${SERVICE_NAME} -f"
	else
		echo "  systemctl status ${SERVICE_NAME}"
		echo "  journalctl -u ${SERVICE_NAME} -f"
	fi
}

if [ "${CELMUX_INSTALL_LIB_ONLY:-0}" != "1" ]; then
	main "$@"
fi
