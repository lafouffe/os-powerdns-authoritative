#!/bin/sh
# Bootstrap installer for os-powerdns-authoritative on OPNsense/FreeBSD.
# Usage:
#   fetch -qo- https://raw.githubusercontent.com/lafouffe/os-powerdns-authoritative/main/scripts/bootstrap-opnsense.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/lafouffe/os-powerdns-authoritative/main/scripts/bootstrap-opnsense.sh | sh
set -eu

REPO="${REPO:-lafouffe/os-powerdns-authoritative}"
VERSION="${VERSION:-v0.1.8}"
VERSION_NUM="${VERSION#v}"
WORKDIR="${WORKDIR:-/tmp/os-powerdns-authoritative-install}"
INSTALL_METHOD="${INSTALL_METHOD:-pkg}"
INSTALL_POWERDNS="${INSTALL_POWERDNS:-binary}"
RESTART_WEBGUI="${RESTART_WEBGUI:-yes}"
PLUGIN_PKG_URL="${PLUGIN_PKG_URL:-https://github.com/${REPO}/releases/download/${VERSION}/os-powerdns-authoritative-${VERSION_NUM}.pkg}"
BINARY_BUNDLE_URL="${BINARY_BUNDLE_URL:-https://github.com/${REPO}/releases/download/${VERSION}/powerdns-binary-bundle-OPNsense-26.1-amd64-${VERSION}.tar.gz}"
ARCHIVE_URL="${ARCHIVE_URL:-https://github.com/${REPO}/releases/download/${VERSION}/os-powerdns-authoritative.tgz}"

log() { printf '%s\n' "$*"; }
run() { log "+ $*"; "$@"; }

fetch_url() {
  url="$1"
  dest="$2"
  if command -v fetch >/dev/null 2>&1; then
    fetch -o "$dest" "$url"
  elif command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$dest"
  else
    echo "ERROR: neither fetch nor curl is available" >&2
    exit 1
  fi
}

install_powerdns_binary_bundle() {
  log "Installing bundled PowerDNS binary packages from ${BINARY_BUNDLE_URL}"
  fetch_url "$BINARY_BUNDLE_URL" "$WORKDIR/powerdns-binary-bundle.tar.gz"
  run mkdir -p "$WORKDIR/powerdns-binary-bundle"
  run tar -xzf "$WORKDIR/powerdns-binary-bundle.tar.gz" -C "$WORKDIR/powerdns-binary-bundle"
  run sh "$WORKDIR/powerdns-binary-bundle/install-bundled-powerdns.sh"
}

prepare_powerdns_baseline() {
  helper="/usr/local/opnsense/scripts/OPNsense/PowerDNS/install-powerdns-opnsense.sh"
  if [ -x "$helper" ]; then
    INSTALL_POWERDNS=no sh "$helper"
  else
    echo "WARN: PowerDNS baseline helper not found at $helper" >&2
  fi
}

install_plugin_pkg() {
  log "Installing OPNsense plugin package from ${PLUGIN_PKG_URL}"
  fetch_url "$PLUGIN_PKG_URL" "$WORKDIR/os-powerdns-authoritative.pkg"
  run pkg add -f "$WORKDIR/os-powerdns-authoritative.pkg"
}

install_plugin_legacy_archive() {
  log "Installing legacy tar archive from ${ARCHIVE_URL}"
  fetch_url "$ARCHIVE_URL" "$WORKDIR/os-powerdns-authoritative.tgz"
  run tar -xzf "$WORKDIR/os-powerdns-authoritative.tgz" -C "$WORKDIR" --strip-components 1

  case "$INSTALL_POWERDNS" in
    no|false|skip)
      log "Skipping PowerDNS package/config bootstrap because INSTALL_POWERDNS=$INSTALL_POWERDNS"
      ;;
    *)
      log "Installing/preparing PowerDNS Authoritative with INSTALL_POWERDNS=$INSTALL_POWERDNS"
      INSTALL_POWERDNS="$INSTALL_POWERDNS" sh "$WORKDIR/scripts/install-powerdns-opnsense.sh"
      ;;
  esac

  log "Installing OPNsense MVC plugin files"
  run mkdir -p \
    /usr/local/opnsense/mvc/app/models/OPNsense \
    /usr/local/opnsense/mvc/app/controllers/OPNsense \
    /usr/local/opnsense/mvc/app/views/OPNsense \
    /usr/local/opnsense/scripts/OPNsense \
    /usr/local/opnsense/service/conf/actions.d

  run cp -a "$WORKDIR/src/opnsense/mvc/app/models/OPNsense/PowerDNS" /usr/local/opnsense/mvc/app/models/OPNsense/
  run cp -a "$WORKDIR/src/opnsense/mvc/app/controllers/OPNsense/PowerDNS" /usr/local/opnsense/mvc/app/controllers/OPNsense/
  run cp -a "$WORKDIR/src/opnsense/mvc/app/views/OPNsense/PowerDNS" /usr/local/opnsense/mvc/app/views/OPNsense/
  run cp -a "$WORKDIR/src/opnsense/scripts/OPNsense/PowerDNS" /usr/local/opnsense/scripts/OPNsense/
  run cp -a "$WORKDIR/src/opnsense/service/conf/actions.d/actions_powerdns.conf" /usr/local/opnsense/service/conf/actions.d/actions_powerdns.conf

  run chmod 755 /usr/local/opnsense/scripts/OPNsense/PowerDNS/*.py
  run chown -R root:wheel \
    /usr/local/opnsense/mvc/app/models/OPNsense/PowerDNS \
    /usr/local/opnsense/mvc/app/controllers/OPNsense/PowerDNS \
    /usr/local/opnsense/mvc/app/views/OPNsense/PowerDNS \
    /usr/local/opnsense/scripts/OPNsense/PowerDNS \
    /usr/local/opnsense/service/conf/actions.d/actions_powerdns.conf

  run service configd restart
  [ "$RESTART_WEBGUI" = "yes" ] && configctl webgui restart || true
}

if [ "$(id -u)" != "0" ]; then
  echo "ERROR: run as root" >&2
  exit 1
fi

if ! uname -s | grep -qi 'freebsd'; then
  echo "ERROR: this bootstrap installer is for OPNsense/FreeBSD" >&2
  exit 1
fi

run rm -rf "$WORKDIR"
run mkdir -p "$WORKDIR"

case "$INSTALL_METHOD" in
  pkg)
    case "$INSTALL_POWERDNS" in
      no|false|skip)
        log "Skipping PowerDNS binary install because INSTALL_POWERDNS=$INSTALL_POWERDNS"
        ;;
      binary|auto|yes|true)
        if command -v pdns_server >/dev/null 2>&1; then
          log "PowerDNS server binary already present; skipping binary bundle install"
        else
          install_powerdns_binary_bundle
        fi
        ;;
      pkg)
        run pkg install -y powerdns sqlite3
        ;;
      ports)
        echo "ERROR: ports build is no longer the bootstrap default. Use INSTALL_METHOD=archive INSTALL_POWERDNS=ports PORTS_FETCH=yes only if you explicitly want ports." >&2
        exit 1
        ;;
      *)
        echo "ERROR: unsupported INSTALL_POWERDNS=$INSTALL_POWERDNS" >&2
        exit 1
        ;;
    esac
    install_plugin_pkg
    case "$INSTALL_POWERDNS" in
      no|false|skip) ;;
      *) prepare_powerdns_baseline ;;
    esac
    ;;
  archive|tar|tgz)
    install_plugin_legacy_archive
    ;;
  *)
    echo "ERROR: unsupported INSTALL_METHOD=$INSTALL_METHOD (use pkg or archive)" >&2
    exit 1
    ;;
esac

if [ "$RESTART_WEBGUI" = "yes" ]; then
  configctl webgui restart || true
fi

cat <<EOF

Done.

Open OPNsense:
  Services > PowerDNS Authoritative

Installed via: ${INSTALL_METHOD}
PowerDNS install mode: ${INSTALL_POWERDNS}

Useful override examples:
  VERSION=${VERSION} fetch -qo- https://raw.githubusercontent.com/${REPO}/main/scripts/bootstrap-opnsense.sh | sh
  INSTALL_POWERDNS=no fetch -qo- https://raw.githubusercontent.com/${REPO}/main/scripts/bootstrap-opnsense.sh | sh
  INSTALL_METHOD=archive fetch -qo- https://raw.githubusercontent.com/${REPO}/main/scripts/bootstrap-opnsense.sh | sh
EOF
