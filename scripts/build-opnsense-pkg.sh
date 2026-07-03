#!/bin/sh
# Build a FreeBSD/OPNsense pkg for the os-powerdns-authoritative GUI plugin.
# Must run on FreeBSD/OPNsense with pkg(8) available.
set -eu

VERSION="${VERSION:-0.1.8}"
REPO_ROOT="${REPO_ROOT:-$(pwd)}"
WORKDIR="${WORKDIR:-/tmp/os-powerdns-authoritative-pkg}"
OUTDIR="${OUTDIR:-${REPO_ROOT}/dist}"
PKG_NAME="os-powerdns-authoritative"
ORIGIN="opnsense/${PKG_NAME}"

if ! uname -s | grep -qi FreeBSD; then
  echo "ERROR: build-opnsense-pkg.sh must run on FreeBSD/OPNsense" >&2
  exit 1
fi
if ! command -v pkg >/dev/null 2>&1; then
  echo "ERROR: pkg command not found" >&2
  exit 1
fi

rm -rf "$WORKDIR"
mkdir -p "$WORKDIR/stage" "$WORKDIR/meta" "$OUTDIR"

copy_tree() {
  src="$1"
  dst="$2"
  mkdir -p "$(dirname "$dst")"
  cp -a "$src" "$dst"
}

copy_tree "$REPO_ROOT/src/opnsense/mvc/app/models/OPNsense/PowerDNS" "$WORKDIR/stage/usr/local/opnsense/mvc/app/models/OPNsense/PowerDNS"
copy_tree "$REPO_ROOT/src/opnsense/mvc/app/controllers/OPNsense/PowerDNS" "$WORKDIR/stage/usr/local/opnsense/mvc/app/controllers/OPNsense/PowerDNS"
copy_tree "$REPO_ROOT/src/opnsense/mvc/app/views/OPNsense/PowerDNS" "$WORKDIR/stage/usr/local/opnsense/mvc/app/views/OPNsense/PowerDNS"
copy_tree "$REPO_ROOT/src/opnsense/scripts/OPNsense/PowerDNS" "$WORKDIR/stage/usr/local/opnsense/scripts/OPNsense/PowerDNS"
copy_tree "$REPO_ROOT/scripts/install-powerdns-opnsense.sh" "$WORKDIR/stage/usr/local/opnsense/scripts/OPNsense/PowerDNS/install-powerdns-opnsense.sh"
copy_tree "$REPO_ROOT/src/opnsense/service/conf/actions.d/actions_powerdns.conf" "$WORKDIR/stage/usr/local/opnsense/service/conf/actions.d/actions_powerdns.conf"

find "$WORKDIR/stage" -type d -name '__pycache__' -prune -exec rm -rf {} +
find "$WORKDIR/stage" -type f -name '*.pyc' -delete
find "$WORKDIR/stage/usr/local/opnsense/scripts/OPNsense/PowerDNS" -type f -name '*.py' -exec chmod 0755 {} +
chmod 0755 "$WORKDIR/stage/usr/local/opnsense/scripts/OPNsense/PowerDNS/install-powerdns-opnsense.sh"
find "$WORKDIR/stage" -type f | sort | sed "s#^$WORKDIR/stage##" > "$WORKDIR/plist"

cat > "$WORKDIR/meta/+MANIFEST" <<EOF
name: "${PKG_NAME}"
version: "${VERSION}"
origin: "${ORIGIN}"
comment: "OPNsense GUI plugin for PowerDNS Authoritative"
maintainer: "lafouffe"
www: "https://github.com/lafouffe/os-powerdns-authoritative"
prefix: "/"
licenselogic: "single"
licenses: [ "MIT" ]
categories: [ "dns", "opnsense" ]
arch: "$(pkg config ABI | sed 's/:.*//'):*"
desc: <<EOD
Lightweight OPNsense MVC plugin for managing PowerDNS Authoritative.
Includes service controls, pdns.conf rendering, API key handling,
authoritative zone/RRset management, and text-mode zone editing.
EOD
scripts: {
  post-install: <<EOS
#!/bin/sh
chmod 755 /usr/local/opnsense/scripts/OPNsense/PowerDNS/*.py 2>/dev/null || true
chown -R root:wheel \
  /usr/local/opnsense/mvc/app/models/OPNsense/PowerDNS \
  /usr/local/opnsense/mvc/app/controllers/OPNsense/PowerDNS \
  /usr/local/opnsense/mvc/app/views/OPNsense/PowerDNS \
  /usr/local/opnsense/scripts/OPNsense/PowerDNS \
  /usr/local/opnsense/service/conf/actions.d/actions_powerdns.conf 2>/dev/null || true
service configd restart 2>/dev/null || true
configctl webgui restart 2>/dev/null || true
EOS
  post-deinstall: <<EOS
#!/bin/sh
service configd restart 2>/dev/null || true
configctl webgui restart 2>/dev/null || true
EOS
}
EOF

pkg create -r "$WORKDIR/stage" -m "$WORKDIR/meta" -p "$WORKDIR/plist" -o "$OUTDIR"
# Normalize filename for release assets regardless of pkg's exact ABI suffix behavior.
created="$(ls -t "$OUTDIR"/${PKG_NAME}-*.pkg | head -1)"
final="$OUTDIR/${PKG_NAME}-${VERSION}.pkg"
if [ "$created" != "$final" ]; then
  mv "$created" "$final"
fi
sha256 "$final" 2>/dev/null || sha256sum "$final"
echo "$final"
