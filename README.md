# os-powerdns-authoritative

Lightweight OPNsense GUI plugin for managing PowerDNS Authoritative.

This project focuses on running PowerDNS Authoritative directly on OPNsense while keeping the UI small, explicit, and firewall-safe.

## Features

- Enable, disable, start, stop, restart, and check `pdns` from the OPNsense GUI.
- Render and manage `/usr/local/etc/pdns/pdns.conf`.
- Configure core PowerDNS settings:
  - backend (`gsqlite3` or `bind`)
  - SQLite database path
  - listen interfaces, with current IPv4 resolution
  - optional listen address override
  - local port
  - service user/group
  - log level
  - webserver/API address, port, allow-from, and API key
  - safe custom `pdns.conf` options
- Basic zone/RRset UI through the PowerDNS HTTP API:
  - list zones
  - list RRsets
  - add/edit/delete RRsets
- No reverse proxy, ACME, Let's Encrypt, or DNS-challenge logic.

## Scope and safety

This plugin intentionally does not manage:

- firewall/NAT rules
- registrar delegation
- DNSSEC DS publication
- ACME/lego/Zoraxy automation
- recursive DNS

Those are deployment-specific concerns and should be handled separately.

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

## Install PowerDNS on OPNsense

A generic helper script is included:

```sh
sudo ./scripts/install-powerdns-opnsense.sh
```

The script:

- installs `powerdns` and `sqlite3` via `pkg`
- creates a generic SQLite backend database if missing
- writes a safe localhost-only baseline `pdns.conf` if missing
- does not configure site-specific IPs, zones, API ACLs, firewall rules, or registrar delegation
- does not start PowerDNS by default

Useful environment variables:

```sh
PDNS_DB=/var/db/pdns/pdns.sqlite3 \
PDNS_CONF=/usr/local/etc/pdns/pdns.conf \
ENABLE_SERVICE=no \
./scripts/install-powerdns-opnsense.sh
```

## Install the plugin prototype manually

Until packaged as a FreeBSD/OPNsense plugin, copy the tree into place:

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

The menu appears under:

```text
Services > PowerDNS Authoritative
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
