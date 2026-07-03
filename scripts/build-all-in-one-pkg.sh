#!/bin/sh
# Build a single all-in-one FreeBSD/OPNsense pkg containing:
# - the os-powerdns-authoritative OPNsense GUI plugin
# - embedded binary pkg files for PowerDNS Authoritative and direct runtime deps
#
# The package post-install cannot run nested pkg add synchronously because pkg(8)
# keeps an exclusive DB lock during scripts. Instead it starts a deferred local
# installer that waits for the lock to clear, then installs embedded packages.
set -eu

VERSION="${VERSION:-0.1.9}"
REPO_ROOT="${REPO_ROOT:-$(pwd)}"
WORKDIR="${WORKDIR:-/tmp/os-powerdns-authoritative-aio-pkg}"
OUTDIR="${OUTDIR:-${REPO_ROOT}/dist}"
PKG_NAME="os-powerdns-authoritative-all-in-one"
ORIGIN="opnsense/${PKG_NAME}"
PACKAGES="${PACKAGES:-openssl libsodium lua54 curl boost-libs sqlite3 powerdns}"
PAYLOAD_DIR="/usr/local/opnsense/scripts/OPNsense/PowerDNS"
EMBEDDED_DIR="${PAYLOAD_DIR}/embedded-packages"
LOG_FILE="/var/log/os-powerdns-authoritative-install.log"

if ! uname -s | grep -qi FreeBSD; then
  echo "ERROR: build-all-in-one-pkg.sh must run on FreeBSD/OPNsense" >&2
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
copy_tree "$REPO_ROOT/src/opnsense/scripts/OPNsense/PowerDNS" "$WORKDIR/stage${PAYLOAD_DIR}"
copy_tree "$REPO_ROOT/scripts/install-powerdns-opnsense.sh" "$WORKDIR/stage${PAYLOAD_DIR}/install-powerdns-opnsense.sh"
copy_tree "$REPO_ROOT/src/opnsense/service/conf/actions.d/actions_powerdns.conf" "$WORKDIR/stage/usr/local/opnsense/service/conf/actions.d/actions_powerdns.conf"

mkdir -p "$WORKDIR/stage${EMBEDDED_DIR}"
for pkgname in $PACKAGES; do
  if ! pkg info "$pkgname" >/dev/null 2>&1; then
    echo "ERROR: required installed package missing: $pkgname" >&2
    echo "Install or build it once on this builder host, then rerun." >&2
    exit 1
  fi
  pkg create -o "$WORKDIR/stage${EMBEDDED_DIR}" "$pkgname"
done

cat > "$WORKDIR/stage${PAYLOAD_DIR}/run-all-in-one-install.sh" <<'EOS'
#!/bin/sh
set -u
LOG_FILE="/var/log/os-powerdns-authoritative-install.log"
PAYLOAD_DIR="/usr/local/opnsense/scripts/OPNsense/PowerDNS"
EMBEDDED_DIR="${PAYLOAD_DIR}/embedded-packages"
HELPER="${PAYLOAD_DIR}/install-powerdns-opnsense.sh"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"; }
run_logged() {
  log "+ $*"
  "$@" >> "$LOG_FILE" 2>&1
}

embedded_pkg_name() {
  pkg info -F "$1" 2>/dev/null | awk -F: '/^Name[[:space:]]*:/ {gsub(/^[[:space:]]+/, "", $2); print $2; exit}'
}

install_one_pkg() {
  file="$1"
  base="$(basename "$file")"
  pkgname="$(embedded_pkg_name "$file")"
  attempt=1
  while [ "$attempt" -le 40 ]; do
    if [ -n "$pkgname" ] && pkg info -e "$pkgname" >/dev/null 2>&1; then
      log "Skipping ${base}; package ${pkgname} is already installed"
      return 0
    fi
    log "Installing embedded package ${base}, attempt ${attempt}"
    if pkg add "$file" >> "$LOG_FILE" 2>&1; then
      log "Installed ${base}"
      return 0
    fi
    log "Install failed for ${base}; pkg DB may still be locked, retrying"
    sleep 3
    attempt=$((attempt + 1))
  done
  log "ERROR: failed to install ${base} after retries"
  return 1
}

main() {
  log "Starting os-powerdns-authoritative all-in-one deferred install"
  if [ ! -d "$EMBEDDED_DIR" ]; then
    log "ERROR: embedded package directory missing: $EMBEDDED_DIR"
    exit 1
  fi

  # Wait a bit so the parent pkg add can finish and release the database lock.
  sleep 5

  # Dependencies first, PowerDNS last.
  for pattern in openssl libsodium lua54 curl boost-libs sqlite3 powerdns; do
    for file in "$EMBEDDED_DIR"/${pattern}-*.pkg; do
      [ -f "$file" ] || continue
      install_one_pkg "$file" || exit 1
    done
  done

  if [ -x "$HELPER" ]; then
    log "Preparing PowerDNS baseline with helper"
    ENABLE_SERVICE=yes INSTALL_POWERDNS=no sh "$HELPER" >> "$LOG_FILE" 2>&1 || log "WARN: helper exited with $?"
  else
    log "WARN: helper not executable: $HELPER"
  fi

  run_logged service configd restart || true
  run_logged configctl webgui restart || true
  run_logged configctl powerdns status || true
  log "Completed os-powerdns-authoritative all-in-one deferred install"
}

main "$@"
EOS
chmod 0755 "$WORKDIR/stage${PAYLOAD_DIR}/run-all-in-one-install.sh"

cat > "$WORKDIR/stage${PAYLOAD_DIR}/README-all-in-one.txt" <<EOF
os-powerdns-authoritative all-in-one package

This package embeds PowerDNS Authoritative and direct runtime dependency pkg files.
After pkg add installs this package, a deferred local installer runs automatically
because pkg(8) keeps the package database locked during post-install scripts.

Log file:
  ${LOG_FILE}

Embedded packages:
$(for pkgname in $PACKAGES; do pkg info -x "^${pkgname}" | sed 's/^/- /'; done)
EOF

find "$WORKDIR/stage" -type d -name '__pycache__' -prune -exec rm -rf {} +
find "$WORKDIR/stage" -type f -name '*.pyc' -delete
find "$WORKDIR/stage${PAYLOAD_DIR}" -type f \( -name '*.py' -o -name '*.sh' \) -exec chmod 0755 {} +
find "$WORKDIR/stage" -type f | sort | sed "s#^$WORKDIR/stage##" > "$WORKDIR/plist"

cat > "$WORKDIR/meta/+MANIFEST" <<EOF
name: "${PKG_NAME}"
version: "${VERSION}"
origin: "${ORIGIN}"
comment: "All-in-one OPNsense PowerDNS Authoritative plugin and binaries"
maintainer: "lafouffe"
www: "https://github.com/lafouffe/os-powerdns-authoritative"
prefix: "/"
licenselogic: "single"
licenses: [ "MIT" ]
categories: [ "dns", "opnsense" ]
arch: "$(pkg config ABI | sed 's/:.*//'):*"
desc: <<EOD
All-in-one OPNsense package for PowerDNS Authoritative.
Includes the OPNsense MVC plugin and embedded binary pkg files for PowerDNS
and direct runtime dependencies. No external pkg repository or ports build is
required for matching OPNsense/FreeBSD amd64 systems.
EOD
scripts: {
  post-install: <<EOS
#!/bin/sh
LOG="${LOG_FILE}"
echo "$(date '+%Y-%m-%d %H:%M:%S') Scheduling all-in-one deferred install" >> "${LOG_FILE}"
/usr/sbin/daemon -p /var/run/os-powerdns-authoritative-install.pid /bin/sh "${PAYLOAD_DIR}/run-all-in-one-install.sh" >/dev/null 2>&1 || \
  ( /bin/sh -c "sleep 8; /bin/sh '${PAYLOAD_DIR}/run-all-in-one-install.sh'" >/dev/null 2>&1 & )
echo "All-in-one PowerDNS install scheduled. Watch ${LOG_FILE} for progress."
EOS
  post-deinstall: <<EOS
#!/bin/sh
service configd restart 2>/dev/null || true
configctl webgui restart 2>/dev/null || true
EOS
}
EOF

pkg create -r "$WORKDIR/stage" -m "$WORKDIR/meta" -p "$WORKDIR/plist" -o "$OUTDIR"
created="$(ls -t "$OUTDIR"/${PKG_NAME}-*.pkg | head -1)"
final="$OUTDIR/${PKG_NAME}-${VERSION}.pkg"
if [ "$created" != "$final" ]; then
  mv "$created" "$final"
fi
sha256 "$final" 2>/dev/null || sha256sum "$final"
echo "$final"
