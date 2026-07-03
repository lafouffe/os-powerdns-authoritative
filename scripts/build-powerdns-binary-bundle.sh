#!/bin/sh
# Build a tar.gz containing binary pkg files for PowerDNS Authoritative and
# its direct runtime dependencies. Must run on a matching OPNsense/FreeBSD ABI.
set -eu

VERSION="${VERSION:-0.1.8}"
OUTDIR="${OUTDIR:-$(pwd)/dist}"
WORKDIR="${WORKDIR:-/tmp/powerdns-binary-bundle}"
BUNDLE_NAME="${BUNDLE_NAME:-powerdns-binary-bundle-OPNsense-26.1-amd64-${VERSION}.tar.gz}"
PACKAGES="${PACKAGES:-powerdns openssl libsodium lua54 curl boost-libs sqlite3}"

if ! uname -s | grep -qi FreeBSD; then
  echo "ERROR: build-powerdns-binary-bundle.sh must run on FreeBSD/OPNsense" >&2
  exit 1
fi
if ! command -v pkg >/dev/null 2>&1; then
  echo "ERROR: pkg command not found" >&2
  exit 1
fi

rm -rf "$WORKDIR"
mkdir -p "$WORKDIR/packages" "$OUTDIR"

for pkgname in $PACKAGES; do
  if ! pkg info "$pkgname" >/dev/null 2>&1; then
    echo "ERROR: required installed package missing: $pkgname" >&2
    echo "Install or build it once on this builder host, then rerun." >&2
    exit 1
  fi
  pkg create -o "$WORKDIR/packages" "$pkgname"
done

cat > "$WORKDIR/install-bundled-powerdns.sh" <<'EOF'
#!/bin/sh
# Install the bundled PowerDNS binary packages from this directory.
set -eu
DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
if ! command -v pkg >/dev/null 2>&1; then
  echo "ERROR: pkg command not found" >&2
  exit 1
fi
# Install dependency packages first, then PowerDNS. pkg add is idempotent enough
# for already-installed packages and avoids any ports build.
for pattern in openssl libsodium lua54 curl boost-libs sqlite3 powerdns; do
  for file in "$DIR"/packages/${pattern}-*.pkg; do
    [ -f "$file" ] || continue
    echo "+ pkg add -f $file"
    pkg add -f "$file"
  done
done
EOF
chmod 0755 "$WORKDIR/install-bundled-powerdns.sh"

cat > "$WORKDIR/README.txt" <<EOF
PowerDNS binary bundle for OPNsense/FreeBSD.

Built on: $(uname -a)
ABI: $(pkg config ABI)
Included packages:
$(for pkgname in $PACKAGES; do pkg info -x "^${pkgname}" | sed 's/^/- /'; done)

Install:
  sh install-bundled-powerdns.sh

This bundle avoids fetching/building the OPNsense ports tree on the target host.
It is intended for matching OPNsense/FreeBSD amd64 systems.
EOF

( cd "$WORKDIR" && tar -czf "$OUTDIR/$BUNDLE_NAME" README.txt install-bundled-powerdns.sh packages )
sha256 "$OUTDIR/$BUNDLE_NAME" 2>/dev/null || sha256sum "$OUTDIR/$BUNDLE_NAME"
echo "$OUTDIR/$BUNDLE_NAME"
