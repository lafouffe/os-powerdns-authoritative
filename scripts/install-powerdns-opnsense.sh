#!/bin/sh
# Prepare PowerDNS Authoritative on OPNsense/FreeBSD.
# This script intentionally does not configure site-specific listener IPs,
# ACLs, zones, registrar delegation, or firewall rules.
set -eu

PDNS_USER="${PDNS_USER:-pdns}"
PDNS_GROUP="${PDNS_GROUP:-pdns}"
PDNS_DB="${PDNS_DB:-/var/db/pdns/pdns.sqlite3}"
PDNS_CONF="${PDNS_CONF:-/usr/local/etc/pdns/pdns.conf}"
ENABLE_SERVICE="${ENABLE_SERVICE:-no}"
BACKEND="${BACKEND:-gsqlite3}"
INSTALL_POWERDNS="${INSTALL_POWERDNS:-auto}"
TRY_PKG="${TRY_PKG:-yes}"
INSTALL_SQLITE="${INSTALL_SQLITE:-auto}"
PORTSDIR="${PORTSDIR:-/usr/ports}"
PDNS_PORT_DIR="${PDNS_PORT_DIR:-/usr/ports/dns/powerdns}"
PORTS_FETCH="${PORTS_FETCH:-no}"
PORTS_MAKE_ARGS="${PORTS_MAKE_ARGS:--DBATCH}"

log() { printf '%s\n' "$*"; }
run() { log "+ $*"; "$@"; }
has_cmd() { command -v "$1" >/dev/null 2>&1; }

if [ "$(id -u)" != "0" ]; then
  echo "ERROR: run as root" >&2
  exit 1
fi

if ! uname -s | grep -qi 'freebsd'; then
  echo "ERROR: this installer is for OPNsense/FreeBSD" >&2
  exit 1
fi

log "Preparing PowerDNS Authoritative baseline"
log "INSTALL_POWERDNS=$INSTALL_POWERDNS TRY_PKG=$TRY_PKG PORTS_FETCH=$PORTS_FETCH"

ensure_pkg() {
  if ! has_cmd pkg; then
    echo "ERROR: pkg command not found" >&2
    exit 1
  fi
}

install_powerdns_with_pkg() {
  ensure_pkg
  log "Trying lightweight package install: pkg install -y powerdns"
  pkg install -y powerdns
}

install_powerdns_from_ports() {
  if [ ! -d "$PDNS_PORT_DIR" ]; then
    if [ "$PORTS_FETCH" = "yes" ]; then
      if has_cmd opnsense-code; then
        log "Fetching OPNsense ports tree because PORTS_FETCH=yes"
        run opnsense-code ports
      else
        echo "ERROR: $PDNS_PORT_DIR is missing and opnsense-code is not available" >&2
        exit 1
      fi
    else
      echo "ERROR: PowerDNS is not installed and $PDNS_PORT_DIR is missing." >&2
      echo "To build from ports explicitly, first prepare the ports tree or rerun with:" >&2
      echo "  INSTALL_POWERDNS=ports PORTS_FETCH=yes sh scripts/install-powerdns-opnsense.sh" >&2
      exit 1
    fi
  fi
  log "Building/installing PowerDNS from OPNsense ports: $PDNS_PORT_DIR"
  run make -C "$PDNS_PORT_DIR" $PORTS_MAKE_ARGS install clean
}

if has_cmd pdns_server; then
  log "PowerDNS server binary already present; skipping install"
else
  case "$INSTALL_POWERDNS" in
    no|false|skip)
      log "INSTALL_POWERDNS=$INSTALL_POWERDNS and pdns_server is missing; only filesystem/config preparation will be attempted"
      ;;
    pkg)
      install_powerdns_with_pkg
      ;;
    ports)
      install_powerdns_from_ports
      ;;
    auto)
      if [ "$TRY_PKG" = "yes" ]; then
        if install_powerdns_with_pkg; then
          log "PowerDNS package installed successfully"
        else
          echo "ERROR: pkg install powerdns failed." >&2
          echo "The installer no longer fetches/builds the full ports tree automatically." >&2
          echo "If you really want the ports build, rerun with:" >&2
          echo "  INSTALL_POWERDNS=ports PORTS_FETCH=yes sh scripts/install-powerdns-opnsense.sh" >&2
          exit 1
        fi
      else
        echo "ERROR: pdns_server is missing and TRY_PKG=no." >&2
        echo "Install PowerDNS yourself, or use INSTALL_POWERDNS=pkg, or explicitly INSTALL_POWERDNS=ports PORTS_FETCH=yes." >&2
        exit 1
      fi
      ;;
    *)
      echo "ERROR: unsupported INSTALL_POWERDNS=$INSTALL_POWERDNS (use auto, no, pkg, or ports)" >&2
      exit 1
      ;;
  esac
fi

if [ "$BACKEND" = "gsqlite3" ] && ! has_cmd sqlite3; then
  case "$INSTALL_SQLITE" in
    no|false|skip)
      echo "ERROR: sqlite3 is required for BACKEND=gsqlite3 but INSTALL_SQLITE=$INSTALL_SQLITE" >&2
      exit 1
      ;;
    auto|yes|true)
      ensure_pkg
      run pkg install -y sqlite3
      ;;
    *)
      echo "ERROR: unsupported INSTALL_SQLITE=$INSTALL_SQLITE" >&2
      exit 1
      ;;
  esac
fi

run mkdir -p "$(dirname "$PDNS_DB")" /usr/local/etc/pdns
run chown "$PDNS_USER:$PDNS_GROUP" "$(dirname "$PDNS_DB")" || true
run chmod 0750 "$(dirname "$PDNS_DB")" || true

if [ "$BACKEND" = "gsqlite3" ]; then
  if [ ! -f "$PDNS_DB" ]; then
    if ! has_cmd sqlite3; then
      echo "ERROR: sqlite3 command not available; cannot create $PDNS_DB" >&2
      exit 1
    fi
    log "Creating empty SQLite backend database: $PDNS_DB"
    sqlite3 "$PDNS_DB" <<'SQL'
CREATE TABLE domains (
  id                    INTEGER PRIMARY KEY,
  name                  VARCHAR(255) NOT NULL,
  master                VARCHAR(128) DEFAULT NULL,
  last_check            INTEGER DEFAULT NULL,
  type                  VARCHAR(8) NOT NULL,
  notified_serial       INTEGER DEFAULT NULL,
  account               VARCHAR(40) DEFAULT NULL,
  options               VARCHAR(64000) DEFAULT NULL,
  catalog               VARCHAR(255) DEFAULT NULL
);
CREATE UNIQUE INDEX name_index ON domains(name);
CREATE TABLE records (
  id                    INTEGER PRIMARY KEY,
  domain_id             INTEGER DEFAULT NULL,
  name                  VARCHAR(255) DEFAULT NULL,
  type                  VARCHAR(10) DEFAULT NULL,
  content               VARCHAR(64000) DEFAULT NULL,
  ttl                   INTEGER DEFAULT NULL,
  prio                  INTEGER DEFAULT NULL,
  disabled              BOOLEAN DEFAULT 0,
  ordername             VARCHAR(255),
  auth                  BOOL DEFAULT 1,
  FOREIGN KEY(domain_id) REFERENCES domains(id) ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX rec_name_index ON records(name);
CREATE INDEX nametype_index ON records(name,type);
CREATE INDEX domain_id ON records(domain_id);
CREATE INDEX recordorder ON records(domain_id, ordername);
CREATE TABLE supermasters (
  ip                    VARCHAR(64) NOT NULL,
  nameserver            VARCHAR(255) NOT NULL,
  account               VARCHAR(40) NOT NULL,
  PRIMARY KEY(ip, nameserver)
);
CREATE TABLE comments (
  id                    INTEGER PRIMARY KEY,
  domain_id             INTEGER NOT NULL,
  name                  VARCHAR(255) NOT NULL,
  type                  VARCHAR(10) NOT NULL,
  modified_at           INTEGER NOT NULL,
  account               VARCHAR(40) DEFAULT NULL,
  comment               VARCHAR(64000) NOT NULL,
  FOREIGN KEY(domain_id) REFERENCES domains(id) ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX comments_name_type_idx ON comments(name, type);
CREATE INDEX comments_order_idx ON comments(domain_id, modified_at);
CREATE TABLE domainmetadata (
  id                    INTEGER PRIMARY KEY,
  domain_id             INTEGER NOT NULL,
  kind                  VARCHAR(32),
  content               TEXT,
  FOREIGN KEY(domain_id) REFERENCES domains(id) ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX domainmetadata_idx ON domainmetadata(domain_id, kind);
CREATE TABLE cryptokeys (
  id                    INTEGER PRIMARY KEY,
  domain_id             INTEGER NOT NULL,
  flags                 INTEGER NOT NULL,
  active                BOOL,
  published             BOOL DEFAULT 1,
  content               TEXT,
  FOREIGN KEY(domain_id) REFERENCES domains(id) ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX domainidindex ON cryptokeys(domain_id);
CREATE TABLE tsigkeys (
  id                    INTEGER PRIMARY KEY,
  name                  VARCHAR(255),
  algorithm             VARCHAR(50),
  secret                VARCHAR(255)
);
CREATE UNIQUE INDEX namealgoindex ON tsigkeys(name, algorithm);
SQL
    run chown "$PDNS_USER:$PDNS_GROUP" "$PDNS_DB" || true
    run chmod 0640 "$PDNS_DB" || true
  else
    log "SQLite database already exists: $PDNS_DB"
  fi
fi

if [ ! -f "$PDNS_CONF" ]; then
  log "Writing generic PowerDNS config: $PDNS_CONF"
  cat >"$PDNS_CONF" <<EOF
# Managed baseline generated by install-powerdns-opnsense.sh
# Site-specific listener addresses, API ACLs, and zones should be configured later.
launch=$BACKEND
gsqlite3-database=$PDNS_DB
local-port=53
setuid=$PDNS_USER
setgid=$PDNS_GROUP
loglevel=4
webserver=yes
webserver-address=127.0.0.1
webserver-port=8081
webserver-allow-from=127.0.0.1,::1
api=yes
api-key=
EOF
  run chmod 0600 "$PDNS_CONF"
else
  log "PowerDNS config already exists, leaving untouched: $PDNS_CONF"
fi

if has_cmd sysrc; then
  run sysrc pdns_enable="$ENABLE_SERVICE" || true
fi

if has_cmd pdns_server; then
  log "PowerDNS version:"
  pdns_server --version || true
  log "Checking PowerDNS config:"
  pdns_server --config-dir=/usr/local/etc/pdns --config=check || true
fi

cat <<EOF

Done.

Next steps:
1. Configure listener interface/IPs in the OPNsense PowerDNS Authoritative plugin.
2. Save in the plugin to auto-generate the API key and DNS firewall rules when enabled.
3. Create or import zones.
4. Start the service when configuration has been verified:
   sysrc pdns_enable=yes
   service pdns start

Installer note:
- Default mode no longer fetches/builds the full OPNsense ports tree.
- If your OPNsense repository has no PowerDNS package and you explicitly want ports:
  INSTALL_POWERDNS=ports PORTS_FETCH=yes sh scripts/install-powerdns-opnsense.sh
EOF
