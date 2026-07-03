# os-powerdns-authoritative

Lightweight OPNsense GUI plugin for managing PowerDNS Authoritative.

This project focuses on running PowerDNS Authoritative directly on OPNsense while keeping the UI small, explicit, and firewall-safe.

## Features

- Enable, disable, start, stop, reload, restart, and check `pdns` from an OPNsense-style action toolbar.
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
  install-powerdns-opnsense.sh
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

The bootstrap script downloads the release archive, optionally prepares PowerDNS, installs the OPNsense MVC plugin files, then restarts `configd` and the web GUI.

Useful overrides:

```sh
# Install plugin only, without installing/preparing the PowerDNS package/config
INSTALL_POWERDNS=no fetch -qo- https://raw.githubusercontent.com/lafouffe/os-powerdns-authoritative/main/scripts/bootstrap-opnsense.sh | sh

# Install a specific release
VERSION=v0.1.7 fetch -qo- https://raw.githubusercontent.com/lafouffe/os-powerdns-authoritative/main/scripts/bootstrap-opnsense.sh | sh
```

The menu appears under:

```text
Services > PowerDNS Authoritative
```

## Install PowerDNS helper only

A generic helper script is also included inside the repository/archive:

```sh
sh scripts/install-powerdns-opnsense.sh
```

The helper script:

PowerDNS is prepared in a minimal-first way:

- if `pdns_server` already exists, no package/ports install is attempted
- default `INSTALL_POWERDNS=auto` tries the lightweight package path first (`pkg install -y powerdns`)
- the script no longer fetches/builds the full OPNsense ports tree automatically
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

## Manual plugin install

Until packaged as a FreeBSD/OPNsense plugin, you can still copy the tree into place manually:

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

## Status

Advanced prototype. Not yet packaged as an official OPNsense plugin package.

## License

BSD-2-Clause
