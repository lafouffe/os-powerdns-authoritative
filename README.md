# os-powerdns-authoritative

Lightweight OPNsense GUI plugin for managing PowerDNS Authoritative.

This project focuses on running PowerDNS Authoritative directly on OPNsense while keeping the UI small, explicit, and firewall-safe.

## Features

- FreeBSD/OPNsense `.pkg` release asset for the GUI plugin.
- Optional PowerDNS binary bundle release asset so users do not have to fetch/build the OPNsense ports tree.
- Enable, disable, start, stop, reload, restart, and check `pdns` from native OPNsense service controls.
- Render and manage `/usr/local/etc/pdns/pdns.conf`.
- Configure core PowerDNS settings:
  - backend (`gsqlite3` or `bind`)
  - SQLite database path
  - listen interfaces, with current IPv4 resolution
  - optional listen address override
  - local port
  - webserver/API address, port, allow-from, and API key
  - automatic API key generation when enabled and empty
  - automatic TCP/UDP DNS firewall rules on selected listen interfaces
  - safe custom `pdns.conf` options
- Runtime values are intentionally fixed by the renderer, not exposed in the UI:
  - `setuid=pdns`
  - `setgid=pdns`
  - `loglevel=4`
- Basic zone/RRset UI through the PowerDNS HTTP API:
  - list/create/delete zones
  - list RRsets
  - add/edit/delete RRsets
- Text editor tab for zone-level changes:
  - export RRsets as `name TTL TYPE value` text
  - paste/edit records in a textarea
  - apply back through the PowerDNS HTTP API while preserving SOA RRsets

## Scope and safety

This plugin intentionally does not manage:

- NAT rules
- registrar delegation
- DNSSEC DS publication
- recursive DNS

Firewall behavior:

- When the service is enabled and listen interfaces are selected, the plugin creates missing inbound TCP/UDP rules for the configured DNS port on those interfaces.
- Existing equivalent pass rules are detected and not duplicated.
- The plugin does not remove firewall rules automatically when disabled; review firewall policy manually if you no longer want to expose DNS.

Those remaining items are deployment-specific concerns and should be handled separately.

Default settings are generic and should not expose the PowerDNS API beyond localhost unless explicitly configured.

## Repository layout

```text
src/opnsense/
  mvc/app/controllers/OPNsense/PowerDNS/
  mvc/app/models/OPNsense/PowerDNS/
  mvc/app/views/OPNsense/PowerDNS/
  scripts/OPNsense/PowerDNS/
  service/conf/actions.d/actions_powerdns.conf
scripts/
  bootstrap-opnsense.sh
  install-powerdns-opnsense.sh
  build-opnsense-pkg.sh
  build-powerdns-binary-bundle.sh
tests/
```

## Quick install on OPNsense

Run as root on OPNsense:

```sh
fetch -qo- https://raw.githubusercontent.com/lafouffe/os-powerdns-authoritative/main/scripts/bootstrap-opnsense.sh | sh
```

If `curl` is installed:

```sh
curl -fsSL https://raw.githubusercontent.com/lafouffe/os-powerdns-authoritative/main/scripts/bootstrap-opnsense.sh | sh
```

The bootstrap script defaults to packaged install mode:

1. downloads the release PowerDNS binary bundle and installs the included `.pkg` files when `pdns_server` is missing,
2. downloads and installs the plugin `.pkg`,
3. prepares the SQLite database and safe baseline `pdns.conf`,
4. restarts `configd` and the web GUI.

Useful overrides:

```sh
# Install plugin only, without installing/preparing PowerDNS
INSTALL_POWERDNS=no fetch -qo- https://raw.githubusercontent.com/lafouffe/os-powerdns-authoritative/main/scripts/bootstrap-opnsense.sh | sh

# Install a specific release
VERSION=v0.1.8 fetch -qo- https://raw.githubusercontent.com/lafouffe/os-powerdns-authoritative/main/scripts/bootstrap-opnsense.sh | sh

# Legacy archive/manual-copy install path, kept as a fallback
INSTALL_METHOD=archive fetch -qo- https://raw.githubusercontent.com/lafouffe/os-powerdns-authoritative/main/scripts/bootstrap-opnsense.sh | sh
```

The menu appears under:

```text
Services > PowerDNS Authoritative
```

## Release assets

Current releases publish:

- `os-powerdns-authoritative-X.Y.Z.pkg` — OPNsense plugin package.
- `powerdns-binary-bundle-OPNsense-26.1-amd64-vX.Y.Z.tar.gz` — bundled binary packages for PowerDNS and direct runtime dependencies.
- `os-powerdns-authoritative.tgz` — legacy source/archive fallback.

## Install PowerDNS helper only

A generic helper script is also included in the repository and installed by the plugin package under `/usr/local/opnsense/scripts/OPNsense/PowerDNS/install-powerdns-opnsense.sh`.

```sh
sh scripts/install-powerdns-opnsense.sh
```

The helper script:

- if `pdns_server` already exists, no package/ports install is attempted
- default `INSTALL_POWERDNS=auto` tries the lightweight package path first (`pkg install -y powerdns`)
- no longer fetches/builds the full OPNsense ports tree automatically
- ports builds are explicit only: `INSTALL_POWERDNS=ports PORTS_FETCH=yes`
- creates a generic SQLite backend database if missing
- writes a safe localhost-only baseline `pdns.conf` if missing
- does not configure site-specific IPs, zones, API ACLs, firewall rules, or registrar delegation
- does not start PowerDNS by default

Useful environment variables:

```sh
PDNS_DB=/var/db/pdns/pdns.sqlite3 \
PDNS_CONF=/usr/local/etc/pdns/pdns.conf \
ENABLE_SERVICE=no \
sh scripts/install-powerdns-opnsense.sh
```

## Build release packages

Local tests can run on Linux, but package/binary asset building must run on matching OPNsense/FreeBSD amd64.

```sh
# On OPNsense/FreeBSD from the repository root:
VERSION=0.1.8 sh scripts/build-opnsense-pkg.sh
VERSION=v0.1.8 sh scripts/build-powerdns-binary-bundle.sh
```

Outputs are written to `dist/`.

## Manual plugin install

For development only, you can still copy the tree into place manually:

```sh
cp -a src/opnsense/mvc/app/models/OPNsense/PowerDNS /usr/local/opnsense/mvc/app/models/OPNsense/
cp -a src/opnsense/mvc/app/controllers/OPNsense/PowerDNS /usr/local/opnsense/mvc/app/controllers/OPNsense/
cp -a src/opnsense/mvc/app/views/OPNsense/PowerDNS /usr/local/opnsense/mvc/app/views/OPNsense/
cp -a src/opnsense/scripts/OPNsense/PowerDNS /usr/local/opnsense/scripts/OPNsense/
cp -a src/opnsense/service/conf/actions.d/actions_powerdns.conf /usr/local/opnsense/service/conf/actions.d/
chmod 755 /usr/local/opnsense/scripts/OPNsense/PowerDNS/*.py
service configd restart
configctl webgui restart
```

## Test

Run the local unit tests from the repository root:

```sh
python3 -m unittest discover -s tests -v
```

The tests cover:

- plugin file structure
- config rendering
- unsafe custom option rejection
- interface-based listener resolution
- fake PowerDNS HTTP API client calls
- UI scope boundaries
- package/bootstrap scripts

## Status

Advanced prototype packaged as a GitHub release `.pkg`, not yet submitted to the official OPNsense plugins repository.

## License

BSD-2-Clause
