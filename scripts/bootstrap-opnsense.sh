#!/bin/sh
# Bootstrap installer for os-powerdns-authoritative on OPNsense/FreeBSD.
# Usage:
#   fetch -qo- https://raw.githubusercontent.com/lafouffe/os-powerdns-authoritative/main/scripts/bootstrap-opnsense.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/lafouffe/os-powerdns-authoritative/main/scripts/bootstrap-opnsense.sh | sh
set -eu

REPO="${REPO:-lafouffe/os-powerdns-authoritative}"
VERSION="${VERSION:-v0.1.9}"
VERSION_NUM="${VERSION#v}"
WORKDIR="${WORKDIR:-/tmp/os-powerdns-authoritative-install}"
INSTALL_METHOD="${INSTALL_METHOD:-all-in-one}"
RESTART_WEBGUI="${RESTART_WEBGUI:-yes}"
ALL_IN_ONE_PKG_URL="${ALL_IN_ONE_PKG_URL:-https://github.com/${REPO}/releases/download/${VERSION}/os-powerdns-authoritative-all-in-one-${VERSION_NUM}.pkg}"
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
  all-in-one|aio|pkg)
    log "Installing all-in-one package from ${ALL_IN_ONE_PKG_URL}"
    fetch_url "$ALL_IN_ONE_PKG_URL" "$WORKDIR/os-powerdns-authoritative-all-in-one.pkg"
    if pkg info -e os-powerdns-authoritative >/dev/null 2>&1; then
      log "Removing old split plugin package before all-in-one install"
      run pkg delete -y os-powerdns-authoritative
    fi
    run pkg add -f "$WORKDIR/os-powerdns-authoritative-all-in-one.pkg"
    ;;
  split)
    log "Installing split plugin package and PowerDNS binary bundle"
    fetch_url "$BINARY_BUNDLE_URL" "$WORKDIR/powerdns-binary-bundle.tar.gz"
    run mkdir -p "$WORKDIR/powerdns-binary-bundle"
    run tar -xzf "$WORKDIR/powerdns-binary-bundle.tar.gz" -C "$WORKDIR/powerdns-binary-bundle"
    run sh "$WORKDIR/powerdns-binary-bundle/install-bundled-powerdns.sh"
    fetch_url "$PLUGIN_PKG_URL" "$WORKDIR/os-powerdns-authoritative.pkg"
    run pkg add -f "$WORKDIR/os-powerdns-authoritative.pkg"
    helper="/usr/local/opnsense/scripts/OPNsense/PowerDNS/install-powerdns-opnsense.sh"
    [ -x "$helper" ] && INSTALL_POWERDNS=no sh "$helper"
    ;;
  archive|tar|tgz)
    log "Installing legacy archive from ${ARCHIVE_URL}"
    fetch_url "$ARCHIVE_URL" "$WORKDIR/os-powerdns-authoritative.tgz"
    run tar -xzf "$WORKDIR/os-powerdns-authoritative.tgz" -C "$WORKDIR" --strip-components 1
    INSTALL_POWERDNS="${INSTALL_POWERDNS:-auto}" sh "$WORKDIR/scripts/install-powerdns-opnsense.sh"
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
    run service configd restart
    ;;
  *)
    echo "ERROR: unsupported INSTALL_METHOD=$INSTALL_METHOD (use all-in-one, split, or archive)" >&2
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

For all-in-one install progress, check:
  /var/log/os-powerdns-authoritative-install.log

Useful override examples:
  VERSION=${VERSION} fetch -qo- https://raw.githubusercontent.com/${REPO}/main/scripts/bootstrap-opnsense.sh | sh
  INSTALL_METHOD=split fetch -qo- https://raw.githubusercontent.com/${REPO}/main/scripts/bootstrap-opnsense.sh | sh
  INSTALL_METHOD=archive fetch -qo- https://raw.githubusercontent.com/${REPO}/main/scripts/bootstrap-opnsense.sh | sh
EOF
