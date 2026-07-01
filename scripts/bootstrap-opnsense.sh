#!/bin/sh
# Bootstrap installer for os-powerdns-authoritative on OPNsense/FreeBSD.
# Usage:
#   fetch -qo- https://raw.githubusercontent.com/lafouffe/os-powerdns-authoritative/main/scripts/bootstrap-opnsense.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/lafouffe/os-powerdns-authoritative/main/scripts/bootstrap-opnsense.sh | sh
set -eu

REPO="${REPO:-lafouffe/os-powerdns-authoritative}"
VERSION="${VERSION:-v0.1.1}"
ARCHIVE_URL="${ARCHIVE_URL:-https://github.com/${REPO}/releases/download/${VERSION}/os-powerdns-authoritative.tgz}"
WORKDIR="${WORKDIR:-/tmp/os-powerdns-authoritative-install}"
INSTALL_POWERDNS="${INSTALL_POWERDNS:-yes}"
RESTART_WEBGUI="${RESTART_WEBGUI:-yes}"

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

log "Installing os-powerdns-authoritative ${VERSION} from ${ARCHIVE_URL}"

run rm -rf "$WORKDIR"
run mkdir -p "$WORKDIR"
fetch_url "$ARCHIVE_URL" "$WORKDIR/os-powerdns-authoritative.tgz"
run tar -xzf "$WORKDIR/os-powerdns-authoritative.tgz" -C "$WORKDIR" --strip-components 1

if [ "$INSTALL_POWERDNS" = "yes" ]; then
  log "Installing/preparing PowerDNS Authoritative"
  sh "$WORKDIR/scripts/install-powerdns-opnsense.sh"
else
  log "Skipping PowerDNS package/config bootstrap because INSTALL_POWERDNS=$INSTALL_POWERDNS"
fi

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

log "Checking installed files"
find /usr/local/opnsense/mvc/app/models/OPNsense/PowerDNS \
     /usr/local/opnsense/mvc/app/controllers/OPNsense/PowerDNS \
     -name '*.php' -print | while read f; do php -l "$f" >/dev/null; done

python3 -m compileall -q /usr/local/opnsense/scripts/OPNsense/PowerDNS || true

log "Restarting configd"
service configd restart

if [ "$RESTART_WEBGUI" = "yes" ]; then
  log "Restarting web GUI"
  configctl webgui restart || true
fi

cat <<EOF

Done.

Open OPNsense:
  Services > PowerDNS Authoritative

Recommended first settings:
  - Select the listen interface(s), usually WAN for public authoritative DNS.
  - Generate/set an API key.
  - Keep API webserver on 127.0.0.1 unless another internal tool needs access.
  - Add firewall rules for TCP/UDP 53 only when the zone is ready.

Useful override examples:
  VERSION=v0.1.0 fetch -qo- https://raw.githubusercontent.com/${REPO}/main/scripts/bootstrap-opnsense.sh | sh
  INSTALL_POWERDNS=no fetch -qo- https://raw.githubusercontent.com/${REPO}/main/scripts/bootstrap-opnsense.sh | sh
EOF
