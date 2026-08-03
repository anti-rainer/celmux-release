#!/bin/sh
set -eu
umask 077

APP_NAME="celmux"
SERVICE_NAME="celmux"
REPO="${CELMUX_RELEASE_REPO:-${CELMUX_REPO:-anti-rainer/celmux-release}}"
VERSION="${CELMUX_VERSION:-}"
MIGRATE_VOHIVE="${CELMUX_MIGRATE_VOHIVE:-ask}"
GITHUB_ACCELERATOR="${CELMUX_GITHUB_ACCELERATOR:-https://gh-proxy.com}"
GITHUB_ACCELERATOR="${GITHUB_ACCELERATOR%/}"
TOYBOX_VERSION="0.8.14"
TOOLBOX=""
TOOL_BIN=""

# Toybox publishes statically linked, architecture-specific binaries. Keep
# these URLs and hashes fixed so a missing host utility can be bootstrapped
# without trusting a package mirror or copying anything into the host PATH.
TOYBOX_AMD64_URL="https://landley.net/toybox/bin/toybox-x86_64"
TOYBOX_AMD64_SHA256="836ba9d6821fb3bcd85f4e2c511115d677930796ef76418799e0df95526d4e65"
TOYBOX_ARM64_URL="https://landley.net/toybox/bin/toybox-aarch64"
TOYBOX_ARM64_SHA256="223b5ff5929371225d0bc62fb3b99a148692295fb6f85ad86bb924f689a55ea4"

usage() {
	cat <<EOF
Usage:
  sh install.sh [--version vX.Y.Z] [--repo owner/repo]
      [--migrate-vohive | --no-migrate-vohive]

Environment:
  CELMUX_VERSION       Release tag to install. Defaults to latest GitHub release.
  CELMUX_RELEASE_REPO  GitHub release repo in owner/repo form. Defaults to ${REPO}.
  CELMUX_REPO          Deprecated alias for CELMUX_RELEASE_REPO.
  CELMUX_MIGRATE_VOHIVE  ask|yes|no. Defaults to ask when legacy data exists.
  CELMUX_GITHUB_ACCELERATOR  Optional GitHub download mirror. Defaults to ${GITHUB_ACCELERATOR}.
EOF
}

die() {
	echo "error: $*" >&2
	exit 1
}

while [ $# -gt 0 ]; do
	case "$1" in
		-h|--help)
			usage
			exit 0
			;;
		--version)
			[ $# -ge 2 ] || die "--version requires a value"
			VERSION="$2"
			shift 2
			;;
		--repo)
			[ $# -ge 2 ] || die "--repo requires a value"
			REPO="$2"
			shift 2
			;;
		--migrate-vohive)
			MIGRATE_VOHIVE=yes
			shift
			;;
		--no-migrate-vohive)
			MIGRATE_VOHIVE=no
			shift
			;;
		*)
			die "unknown argument: $1"
			;;
	esac
done

require_root() {
	if [ "$(id -u)" -ne 0 ]; then
		die "please run this installer as root; sudo is optional and is not required on OpenWrt"
	fi
}

detect_init_system() {
	if [ -f /etc/openwrt_release ]; then
		[ -x /etc/rc.common ] || die "OpenWrt rc.common was not found"
		[ -d /etc/init.d ] || die "OpenWrt init directory was not found"
		echo "procd"
		return
	fi
	if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
		echo "systemd"
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

check_download_tool() {
	command -v curl >/dev/null 2>&1 || die "curl is required to download the release"
}

check_bootstrap_tools() {
	check_download_tool
	command -v sha256sum >/dev/null 2>&1 || die "sha256sum is required"
}

fetch_stdout() {
	url="$1"
	curl -fsSL "$url"
}

download() {
	url="$1"
	out="$2"
	curl -fL --retry 3 --retry-delay 2 -o "$out" "$url"
}

try_download() {
	url="$1"
	out="$2"
	curl -fsL --retry 2 --retry-delay 1 -o "$out" "$url"
}

toolbox_metadata() {
	arch="$1"
	case "$arch" in
		amd64)
			TOYBOX_URL="$TOYBOX_AMD64_URL"
			TOYBOX_SHA256="$TOYBOX_AMD64_SHA256"
			;;
		arm64)
			TOYBOX_URL="$TOYBOX_ARM64_URL"
			TOYBOX_SHA256="$TOYBOX_ARM64_SHA256"
			;;
		*)
			die "no static installer helper is available for linux/${arch}"
			;;
	esac
}

download_toolbox() {
	arch="$1"
	tool_dir="$2"
	toolbox_metadata "$arch"
	TOOL_BIN="${tool_dir}/bin"
	TOOLBOX="${tool_dir}/toybox-${arch}"
	mkdir -p "$TOOL_BIN"
	echo "downloading Toybox ${TOYBOX_VERSION} installer helper for linux/${arch}"
	curl -fL --retry 3 --retry-delay 2 -o "$TOOLBOX" "$TOYBOX_URL" ||
		die "unable to download static installer helper for linux/${arch}"
	chmod 0755 "$TOOLBOX"

	if command -v sha256sum >/dev/null 2>&1; then
		actual="$(sha256sum "$TOOLBOX" | awk '{print $1}')"
	else
		# This is only a bootstrap path: TLS plus the embedded digest protects
		# the official helper before it supplies the missing hash command.
		actual="$("$TOOLBOX" sha256sum "$TOOLBOX" | awk '{print $1}')"
	fi
	[ "$actual" = "$TOYBOX_SHA256" ] || die "static installer helper checksum verification failed"

	for applet in sha256sum od; do
		if ! command -v "$applet" >/dev/null 2>&1; then
			ln -s "$TOOLBOX" "$TOOL_BIN/$applet"
		fi
	done
	PATH="${TOOL_BIN}:${PATH}"
	export PATH
}

install_missing_tools() {
	arch="$1"
	tool_dir="$2"
	if command -v sha256sum >/dev/null 2>&1 && command -v od >/dev/null 2>&1; then
		return 0
	fi
	download_toolbox "$arch" "$tool_dir"
}

accelerated_url() {
	url="$1"
	printf '%s/%s\n' "$GITHUB_ACCELERATOR" "$url"
}

try_download_candidates() {
	out="$1"
	shift
	for url in "$@"; do
		if try_download "$url" "$out"; then
			return 0
		fi
	done
	return 1
}

latest_version() {
	json="$(fetch_stdout "https://api.github.com/repos/${REPO}/releases/latest")"
	tag="$(printf '%s\n' "$json" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
	[ -n "$tag" ] || die "unable to resolve latest release for ${REPO}"
	echo "$tag"
}

download_installer() {
	version="$1"
	out="$2"
	download_repository_file "$version" install-local.sh "$out"
}

download_repository_file() {
	version="$1"
	file="$2"
	out="$3"
	if try_download_repository_file "$version" "$file" "$out"; then
		return
	fi
	die "unable to download ${file} from ${REPO}"
}

try_download_repository_file() {
	version="$1"
	file="$2"
	out="$3"
	raw_main="https://raw.githubusercontent.com/${REPO}/main/${file}"
	raw_tag="https://raw.githubusercontent.com/${REPO}/${version}/${file}"
	source_raw_main="https://raw.githubusercontent.com/${REPO}/main/scripts/${file}"
	source_raw_tag="https://raw.githubusercontent.com/${REPO}/${version}/scripts/${file}"
	release_asset="https://github.com/${REPO}/releases/download/${version}/${file}"
	legacy_file="https://github.com/${REPO}/releases/download/${version}/install-debian-binary.sh"

	if try_download_candidates "$out" \
		"$(accelerated_url "$raw_main")" "$raw_main" \
		"$(accelerated_url "$raw_tag")" "$raw_tag" \
		"$(accelerated_url "$source_raw_main")" "$source_raw_main" \
		"$(accelerated_url "$source_raw_tag")" "$source_raw_tag" \
		"$(accelerated_url "$release_asset")" "$release_asset"; then
		return
	fi
	if [ "$file" = "install-local.sh" ] && try_download_candidates "$out" \
		"$(accelerated_url "$legacy_file")" "$legacy_file"; then
		return 0
	fi
	return 1
}

download_checksums() {
	version="$1"
	out="$2"
	if try_download_repository_file "$version" "sha256sums-${version}.txt" "$out"; then
		return
	fi
	download_repository_file "$version" sha256sums.txt "$out"
}

download_release_asset() {
	version="$1"
	asset="$2"
	out="$3"
	direct="https://github.com/${REPO}/releases/download/${version}/${asset}"
	if try_download "$(accelerated_url "$direct")" "$out"; then
		return
	fi
	download "$direct" "$out"
}

verify_release_asset() {
	checksums="$1"
	asset_path="$2"
	asset_name="$3"
	expected="$(awk -v name="$asset_name" '$2 == name { print $1; exit }' "$checksums")"
	[ -n "$expected" ] || die "release checksum is missing for ${asset_name}"
	actual="$(sha256sum "$asset_path" | awk '{print $1}')"
	[ "$actual" = "$expected" ] || die "release checksum verification failed for ${asset_name}"
}

print_access_hint() {
	ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
	if [ -n "$ip" ]; then
		echo "Web: http://${ip}:7575"
	else
		echo "Web: http://<server-ip>:7575"
	fi
}

ensure_restart_always() {
	service="/etc/systemd/system/${SERVICE_NAME}.service"
	if ! command -v systemctl >/dev/null 2>&1 || [ ! -f "$service" ]; then
		return
	fi

	if grep -q '^Restart=' "$service"; then
		sed -i 's/^Restart=.*/Restart=always/' "$service"
	else
		tmp="${service}.tmp"
		awk '
			{ print }
			$0 == "ExecStart=/opt/celmux/bin/celmux -c /opt/celmux/config/config.yaml" {
				print "Restart=always"
			}
		' "$service" > "$tmp"
		mv "$tmp" "$service"
	fi
	systemctl daemon-reload
	systemctl restart "$SERVICE_NAME"
}

main() {
	require_root
	init_system="$(detect_init_system)"
	case "$init_system" in
		systemd)
			if [ ! -f /etc/debian_version ]; then
				echo "warning: Debian was not detected; continuing with systemd" >&2
			fi
			;;
		procd)
			echo "detected OpenWrt/procd"
		;;
	esac

	check_download_tool
	arch="$(detect_arch)"
	tmpdir="$(mktemp -d)"
	trap 'rm -rf "$tmpdir"' EXIT INT TERM
	install_missing_tools "$arch" "${tmpdir}/tools"
	check_bootstrap_tools

	if [ -z "$VERSION" ]; then
		VERSION="$(latest_version)"
	fi
	asset="celmux_linux_${arch}"
	binary="${tmpdir}/${asset}"
	installer="${tmpdir}/install-local.sh"
	checksums="${tmpdir}/sha256sums.txt"
	legal_dir="${tmpdir}/legal"
	mkdir -p "$legal_dir"

	echo "Installing ${APP_NAME} ${VERSION} for linux/${arch} from ${REPO}"
	download_release_asset "$VERSION" "$asset" "$binary"
	chmod 0755 "$binary"
	download_checksums "$VERSION" "$checksums"
	verify_release_asset "$checksums" "$binary" "$asset"

	download_installer "$VERSION" "$installer"
	chmod 0755 "$installer"
	verify_release_asset "$checksums" "$installer" "install-local.sh"

	for legal_file in LICENSE NOTICE.md THIRD_PARTY_NOTICES.md DISCLAIMER.md; do
		download_repository_file "$VERSION" "$legal_file" "${legal_dir}/${legal_file}"
		verify_release_asset "$checksums" "${legal_dir}/${legal_file}" "$legal_file"
	done

	CELMUX_MIGRATE_VOHIVE="$MIGRATE_VOHIVE" \
	CELMUX_LEGAL_SOURCE_DIR="$legal_dir" \
		sh "$installer" "$binary"
	ensure_restart_always
	print_access_hint
}

main "$@"
