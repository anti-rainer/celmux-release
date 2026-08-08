#!/bin/sh
# Celmux installer. Copyright 2026 anti-rainer.
# Usage: curl -fsSL https://ghproxy.net/https://raw.githubusercontent.com/anti-rainer/celmux-release/main/install.sh | sudo bash
set -eu
umask 077

APP_NAME="celmux"
SERVICE_NAME="celmux"
REPO="${CELMUX_RELEASE_REPO:-anti-rainer/celmux-release}"
VERSION="${CELMUX_VERSION:-}"
INSTALL_ROOT="${CELMUX_INSTALL_ROOT:-/opt/celmux}"
INSTALL_BIN="${INSTALL_ROOT}/bin/${APP_NAME}"
CONFIG_DIR="${INSTALL_ROOT}/config"
CONFIG_FILE="${CONFIG_DIR}/celmux.yaml"
GITHUB_ACCELERATOR="${CELMUX_GITHUB_ACCELERATOR:-https://ghproxy.net}"
GITHUB_ACCELERATOR="${GITHUB_ACCELERATOR%/}"
INIT_SYSTEM=""
SERVICE_FILE=""
IS_ANDROID=0

usage() {
	cat <<EOF
Usage:
  sh install.sh [--version X.Y.Z]

Environment:
  CELMUX_VERSION             Release tag. Defaults to the latest release.
  CELMUX_RELEASE_REPO       Release repository. Defaults to ${REPO}.
  CELMUX_INSTALL_ROOT        Install root. Defaults to ${INSTALL_ROOT}.
  CELMUX_GITHUB_ACCELERATOR  Optional GitHub proxy. Empty disables the proxy.
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

require_root() {
	[ "$(id -u)" -eq 0 ] || die "please run this installer as root, for example: curl ... | sudo bash"
}

detect_arch() {
	case "$(uname -m)" in
		x86_64|amd64) echo amd64 ;;
		aarch64|arm64) echo arm64 ;;
		*) die "unsupported architecture: $(uname -m); only linux/amd64 and linux/arm64 are published" ;;
	esac
}

is_openwrt() {
	[ -f /etc/openwrt_release ] || [ -f /etc/openwrt_version ] ||
		{ [ -x /sbin/procd ] && [ -f /lib/functions/procd.sh ]; }
}

detect_environment() {
	if [ -f /system/build.prop ] || [ -d /data/adb ]; then
		IS_ANDROID=1
	fi
}

parse_args() {
	while [ "$#" -gt 0 ]; do
		case "$1" in
			-h|--help)
				usage
				exit 0
				;;
			--version)
				[ "$#" -ge 2 ] || die "--version requires a value"
				VERSION="$2"
				shift 2
				continue
				;;
			*) die "unknown argument: $1" ;;
		esac
		shift
	done
}

validate_version() {
	case "$VERSION" in
		[0-9]*.[0-9]*.[0-9]*) ;;
		*) die "release tag must use the numeric X.Y.Z form: $VERSION" ;;
	esac
}

fetch_api() {
	url="$1"
	if [ -n "$GITHUB_ACCELERATOR" ] && curl -fsSL --retry 2 --retry-delay 1 \
		--connect-timeout 15 -H 'Accept: application/vnd.github+json' \
		"${GITHUB_ACCELERATOR}/${url}"; then
		return 0
	fi
	curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 15 \
		-H 'Accept: application/vnd.github+json' "$url"
}

download() {
	url="$1"
	out="$2"
	if [ -n "$GITHUB_ACCELERATOR" ] && curl -fsSL --retry 2 --retry-delay 1 \
		--connect-timeout 15 -o "$out" "${GITHUB_ACCELERATOR}/${url}"; then
		return 0
	fi
	curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 15 -o "$out" "$url"
}

resolve_latest_version() {
	json="$(fetch_api "https://api.github.com/repos/${REPO}/releases/latest")"
	VERSION="$(printf '%s\n' "$json" |
		sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
		head -n 1)"
	[ -n "$VERSION" ] || die "unable to resolve the latest release for ${REPO}"
}

asset_digest() {
	json="$1"
	asset="$2"
	record="$(printf '%s' "$json" | tr -d '\n\r\t ' | tr '{' '\n' |
		awk -v needle="\"name\":\"${asset}\"" 'index($0, needle) { print; exit }')"
	asset_id="$(printf '%s\n' "$record" |
		sed -n 's/.*"id":\([0-9][0-9]*\).*"name":"'"$asset"'".*/\1/p')"
	[ -n "$asset_id" ] || die "release API did not provide an id for ${asset}"
	asset_json="$(fetch_api "https://api.github.com/repos/${REPO}/releases/assets/${asset_id}")"
	digest="$(printf '%s' "$asset_json" | tr -d '\n\r\t ' |
		sed -n 's/.*"digest":"sha256:\([0-9A-Fa-f]\{64\}\)".*/\1/p')"
	[ -n "$digest" ] || die "release API did not provide a SHA-256 digest for ${asset}"
	printf '%s\n' "$digest"
}

verify_sha256() {
	expected="$1"
	path="$2"
	actual="$(sha256sum "$path" | awk '{print $1}')"
	[ "$actual" = "$expected" ] || die "SHA-256 verification failed for $(basename "$path")"
}

copy_binary() {
	src="$1"
	dst="$2"
	if command -v install >/dev/null 2>&1; then
		install -m 0750 "$src" "${dst}.new"
	else
		cp "$src" "${dst}.new"
		chmod 0750 "${dst}.new"
	fi
	mv -f "${dst}.new" "$dst"
}

detect_init_system() {
	if [ "$IS_ANDROID" -eq 1 ] && [ -d /data/adb ]; then
		INIT_SYSTEM=android
	SERVICE_FILE="/data/adb/service.d/${SERVICE_NAME}.sh"
	return
	fi

	if is_openwrt; then
		[ -x /etc/rc.common ] || die "OpenWrt rc.common was not found"
		[ -d /etc/init.d ] || die "OpenWrt init directory was not found"
		INIT_SYSTEM=procd
		SERVICE_FILE="/etc/init.d/${SERVICE_NAME}"
		return
	fi

	if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
		INIT_SYSTEM=systemd
		SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
		return
	fi
	if command -v rc-service >/dev/null 2>&1 && command -v rc-update >/dev/null 2>&1; then
		INIT_SYSTEM=openrc
		SERVICE_FILE="/etc/init.d/${SERVICE_NAME}"
		return
	fi
	if [ -d /etc/init.d ] && {
		command -v update-rc.d >/dev/null 2>&1 || command -v chkconfig >/dev/null 2>&1
	}; then
		INIT_SYSTEM=sysvinit
		SERVICE_FILE="/etc/init.d/${SERVICE_NAME}"
		return
	fi
	INIT_SYSTEM=unknown
	SERVICE_FILE=""
}

write_systemd_service() {
	cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=celmux modem management service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_ROOT}
ExecStart=${INSTALL_BIN} -c ${CONFIG_FILE}
Restart=always
RestartSec=5s
Environment=CONFIG_PATH=${CONFIG_FILE}
Environment=HOME=${INSTALL_ROOT}
Environment=GODEBUG=madvdontneed=1
Environment=GOMEMLIMIT=72MiB
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
ReadWritePaths=${INSTALL_ROOT}
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
WORK_DIR="${INSTALL_ROOT}"

start_service() {
	procd_open_instance
	procd_set_param command "\$PROG" -c "\$CONFIG"
	procd_set_param env "CONFIG_PATH=\$CONFIG" "HOME=\$WORK_DIR" "GODEBUG=madvdontneed=1" "GOMEMLIMIT=72MiB"
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

write_openrc_service() {
	cat > "$SERVICE_FILE" <<EOF
#!/sbin/openrc-run

name="${SERVICE_NAME}"
description="Celmux modem management service"
command="${INSTALL_BIN}"
command_args="-c ${CONFIG_FILE}"
command_background=true
pidfile="/run/\${RC_SVCNAME}.pid"
directory="${INSTALL_ROOT}"

depend() {
	need net
	after firewall
}
EOF
	chmod 0755 "$SERVICE_FILE"
}

write_sysvinit_service() {
	cat > "$SERVICE_FILE" <<EOF
#!/bin/sh
### BEGIN INIT INFO
# Provides:          ${SERVICE_NAME}
# Required-Start:    \$network \$remote_fs
# Required-Stop:     \$network \$remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Celmux modem management service
### END INIT INFO

DAEMON="${INSTALL_BIN}"
WORK_DIR="${INSTALL_ROOT}"
PIDFILE="/var/run/${SERVICE_NAME}.pid"
LOGFILE="/var/log/${SERVICE_NAME}.log"

is_running() {
    [ -f "\$PIDFILE" ] && kill -0 "\$(cat "\$PIDFILE")" 2>/dev/null
}

case "\$1" in
    start)
        if is_running; then exit 0; fi
        cd "\$WORK_DIR"
        nohup "\$DAEMON" -c "${CONFIG_FILE}" >>"\$LOGFILE" 2>&1 &
        echo \$! >"\$PIDFILE"
        ;;
    stop)
        if is_running; then kill "\$(cat "\$PIDFILE")" 2>/dev/null || true; fi
        rm -f "\$PIDFILE"
        ;;
    restart)
        "\$0" stop
        sleep 1
        "\$0" start
        ;;
    status)
        is_running
        ;;
    *) echo "Usage: \$0 {start|stop|restart|status}" >&2; exit 1 ;;
esac
EOF
	chmod 0755 "$SERVICE_FILE"
}

write_android_service() {
	service_dir="/data/adb/service.d"
	mkdir -p "$service_dir"
	cat > "$SERVICE_FILE" <<EOF
#!/system/bin/sh

CELMUX_DIR="${INSTALL_ROOT}"
CELMUX_BIN="${INSTALL_BIN}"
CELMUX_CONFIG="${CONFIG_FILE}"
PIDFILE="\${CELMUX_DIR}/celmux.pid"

is_running() {
    [ -f "\$PIDFILE" ] && kill -0 "\$(cat "\$PIDFILE")" 2>/dev/null
}

case "\$1" in
    start)
        if is_running; then exit 0; fi
        cd "\$CELMUX_DIR"
        nohup "\$CELMUX_BIN" -c "\$CELMUX_CONFIG" >/dev/null 2>&1 &
        echo \$! >"\$PIDFILE"
        ;;
    stop)
        if is_running; then kill "\$(cat "\$PIDFILE")" 2>/dev/null || true; fi
        rm -f "\$PIDFILE"
        ;;
    restart)
        "\$0" stop
        sleep 1
        "\$0" start
        ;;
    *) echo "Usage: \$0 {start|stop|restart}" >&2; exit 1 ;;
esac
EOF
	chmod 0755 "$SERVICE_FILE"
}

write_service() {
	case "$INIT_SYSTEM" in
		systemd) write_systemd_service ;;
		procd) write_procd_service ;;
		openrc) write_openrc_service ;;
		sysvinit) write_sysvinit_service ;;
		android) write_android_service ;;
		unknown) ;;
		*) die "unsupported init system: $INIT_SYSTEM" ;;
	esac
}

start_service() {
	case "$INIT_SYSTEM" in
		systemd)
			systemctl daemon-reload
			systemctl enable "$SERVICE_NAME.service"
			systemctl restart "$SERVICE_NAME.service"
			;;
		procd)
			"$SERVICE_FILE" enable
			"$SERVICE_FILE" restart
			;;
		openrc)
			rc-update add "$SERVICE_NAME" default
			rc-service "$SERVICE_NAME" restart
			;;
		sysvinit)
			if command -v update-rc.d >/dev/null 2>&1; then
				update-rc.d "$SERVICE_NAME" defaults
			elif command -v chkconfig >/dev/null 2>&1; then
				chkconfig --add "$SERVICE_NAME"
				chkconfig "$SERVICE_NAME" on
			fi
			"$SERVICE_FILE" restart
			;;
		android)
			"$SERVICE_FILE" restart
			;;
		unknown)
			echo "warning: no supported service manager found; binary installed without a service" >&2
			;;
		*) die "unsupported init system: $INIT_SYSTEM" ;;
	esac
}

main() {
	parse_args "$@"
	require_root
	validate_install_root
	detect_environment
	detect_init_system
	command -v curl >/dev/null 2>&1 || die "curl is required"
	command -v sha256sum >/dev/null 2>&1 || die "sha256sum is required"
	ARCH="$(detect_arch)"
	if [ -z "$VERSION" ]; then
		resolve_latest_version
	fi
	validate_version

	TMP_DIR="$(mktemp -d)"
	trap 'rm -rf "$TMP_DIR"' EXIT INT TERM
	ASSET="celmux_linux_${ARCH}"
	RELEASE_JSON="$(fetch_api "https://api.github.com/repos/${REPO}/releases/tags/${VERSION}")"
	DIGEST="$(asset_digest "$RELEASE_JSON" "$ASSET")"
	BINARY_PATH="${TMP_DIR}/${ASSET}"
	ASSET_URL="https://github.com/${REPO}/releases/download/${VERSION}/${ASSET}"

	echo "Installing ${APP_NAME} ${VERSION} for linux/${ARCH}"
	download "$ASSET_URL" "$BINARY_PATH"
	verify_sha256 "$DIGEST" "$BINARY_PATH"

	mkdir -p "${INSTALL_ROOT}/bin" "$CONFIG_DIR" "${INSTALL_ROOT}/data" "${INSTALL_ROOT}/logs"
	chmod 0750 "$INSTALL_ROOT" "${INSTALL_ROOT}/bin" "$CONFIG_DIR" "${INSTALL_ROOT}/data" "${INSTALL_ROOT}/logs"
	copy_binary "$BINARY_PATH" "$INSTALL_BIN"
	write_service
	start_service

	echo "celmux installed: ${INSTALL_BIN}"
	echo "config: ${CONFIG_FILE}"
	echo "service: ${SERVICE_FILE}"
	echo "If config.yaml exists beside celmux.yaml, the binary will import only supported visible settings on first start."
}

main "$@"
