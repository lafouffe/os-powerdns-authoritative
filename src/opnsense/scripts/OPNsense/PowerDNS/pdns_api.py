#!/usr/local/bin/python3
import argparse
import json
import shlex
import sys
import urllib.error
import urllib.parse
import urllib.request
from collections import OrderedDict
try:
    from render_config import load_config_xml
except Exception:
    load_config_xml = None

class PowerDNSError(RuntimeError):
    pass

class PowerDNSClient:
    def __init__(self, host, api_key, server='localhost', timeout=10):
        self.host = host.rstrip('/')
        self.api_key = api_key
        self.server = server
        self.timeout = timeout
    def _url(self, path):
        return self.host + '/api/v1' + path
    def request(self, method, path, body=None):
        data = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(self._url(path), data=data, method=method)
        req.add_header('X-API-Key', self.api_key)
        req.add_header('Content-Type', 'application/json')
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                raw = resp.read().decode()
                return None if not raw else json.loads(raw)
        except urllib.error.HTTPError as e:
            raw = e.read().decode(errors='replace')
            raise PowerDNSError('HTTP %s %s' % (e.code, raw))
    def zone_name(self, zone):
        return zone if zone.endswith('.') else zone + '.'
    def list_zones(self):
        return self.request('GET', f'/servers/{self.server}/zones')
    def get_zone(self, zone):
        zone = self.zone_name(zone)
        return self.request('GET', f'/servers/{self.server}/zones/{urllib.parse.quote(zone)}')
    def create_zone(self, zone, kind='Native', nameservers=None):
        zone = self.zone_name(zone)
        kind = (kind or 'Native').strip()
        body = {'name': zone, 'kind': kind}
        ns = [x.strip() for x in (nameservers or '').split('\n') if x.strip()]
        if ns:
            body['nameservers'] = [self.zone_name(x) for x in ns]
        return self.request('POST', f'/servers/{self.server}/zones', body)
    def delete_zone(self, zone):
        zone = self.zone_name(zone)
        return self.request('DELETE', f'/servers/{self.server}/zones/{urllib.parse.quote(zone)}')
    def upsert_rrset(self, zone, name, rtype, ttl, records):
        zone = self.zone_name(zone)
        name = self.zone_name(name)
        rrset = {'name': name, 'type': rtype.upper(), 'ttl': int(ttl), 'changetype': 'REPLACE',
                 'records': [{'content': r, 'disabled': False} for r in records]}
        return self.request('PATCH', f'/servers/{self.server}/zones/{urllib.parse.quote(zone)}', {'rrsets':[rrset]})
    def delete_rrset(self, zone, name, rtype):
        zone = self.zone_name(zone)
        name = self.zone_name(name)
        rrset = {'name': name, 'type': rtype.upper(), 'changetype': 'DELETE', 'records': []}
        return self.request('PATCH', f'/servers/{self.server}/zones/{urllib.parse.quote(zone)}', {'rrsets':[rrset]})
    def patch_rrsets(self, zone, rrsets):
        zone = self.zone_name(zone)
        return self.request('PATCH', f'/servers/{self.server}/zones/{urllib.parse.quote(zone)}', {'rrsets': rrsets})


def quote_record_content(value):
    value = '' if value is None else str(value)
    if any(ch.isspace() for ch in value) or value == '' or ';' in value or '"' in value:
        return shlex.quote(value)
    return value


def export_zone_text(zone_data):
    rrsets = sorted(zone_data.get('rrsets') or [], key=lambda r: ((r.get('name') or ''), (r.get('type') or '')))
    lines = [
        '; PowerDNS text editor export',
        '; Format: name TTL TYPE value',
        '; Empty lines and lines starting with ; are ignored on import.',
        '; SOA RRsets are exported for visibility but preserved by import.',
        '',
    ]
    count = 0
    for rr in rrsets:
        name = rr.get('name') or ''
        ttl = rr.get('ttl') or 300
        rtype = (rr.get('type') or '').upper()
        records = rr.get('records') or []
        if not records:
            lines.append(f'; {name} {ttl} {rtype}')
            continue
        for record in records:
            if record.get('disabled'):
                lines.append('; disabled: ' + ' '.join([name, str(ttl), rtype, quote_record_content(record.get('content', ''))]))
            else:
                lines.append(' '.join([name, str(ttl), rtype, quote_record_content(record.get('content', ''))]))
                count += 1
    return '\n'.join(lines) + '\n', count


def parse_zone_text(zone, text):
    grouped = OrderedDict()
    zone = zone if zone.endswith('.') else zone + '.'
    for lineno, raw in enumerate((text or '').splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith(';'):
            continue
        try:
            parts = shlex.split(line, comments=False, posix=True)
        except ValueError as exc:
            raise PowerDNSError(f'line {lineno}: {exc}')
        if len(parts) < 4:
            raise PowerDNSError(f'line {lineno}: expected name TTL TYPE value')
        name, ttl, rtype = parts[0], parts[1], parts[2].upper()
        value = ' '.join(parts[3:])
        if name == '@':
            name = zone
        elif not name.endswith('.'):
            name = name + '.'
        try:
            ttl_int = int(ttl)
        except ValueError:
            raise PowerDNSError(f'line {lineno}: invalid TTL {ttl!r}')
        if rtype == 'SOA':
            # Preserve SOA managed by PowerDNS. It is shown in exports for visibility.
            continue
        key = (name, rtype, ttl_int)
        grouped.setdefault(key, []).append(value)
    return grouped


def import_zone_text(client, zone, text):
    zone_data = client.get_zone(zone)
    desired = parse_zone_text(zone, text)
    existing = {}
    for rr in zone_data.get('rrsets') or []:
        rtype = (rr.get('type') or '').upper()
        if rtype == 'SOA':
            continue
        key = (rr.get('name'), rtype)
        existing[key] = rr
    changes = []
    for (name, rtype, ttl), records in desired.items():
        changes.append({
            'name': name,
            'type': rtype,
            'ttl': ttl,
            'changetype': 'REPLACE',
            'records': [{'content': r, 'disabled': False} for r in records],
        })
    desired_keys = {(name, rtype) for (name, rtype, _ttl) in desired.keys()}
    for (name, rtype), rr in existing.items():
        if (name, rtype) not in desired_keys:
            changes.append({'name': name, 'type': rtype, 'changetype': 'DELETE', 'records': []})
    if changes:
        client.patch_rrsets(zone, changes)
    return {'ok': True, 'changed_rrsets': len(changes)}


def client_from_config(path='/conf/config.xml'):
    if load_config_xml is None:
        raise PowerDNSError('unable to load OPNsense PowerDNS config')
    cfg = load_config_xml(path)
    host = 'http://%s:%s' % (cfg.get('webserver_address','127.0.0.1'), cfg.get('webserver_port','8081'))
    return PowerDNSClient(host, cfg.get('api_key',''), 'localhost')

def main(argv=None):
    p = argparse.ArgumentParser()
    p.add_argument('--config', default='/conf/config.xml')
    sub = p.add_subparsers(dest='cmd', required=True)
    sub.add_parser('zones')
    z = sub.add_parser('zone'); z.add_argument('zone')
    xt = sub.add_parser('export-text'); xt.add_argument('zone')
    it = sub.add_parser('import-text'); it.add_argument('zone'); it.add_argument('text')
    cz = sub.add_parser('create-zone'); cz.add_argument('zone'); cz.add_argument('kind'); cz.add_argument('nameservers', nargs='?', default='')
    dz = sub.add_parser('delete-zone'); dz.add_argument('zone')
    u = sub.add_parser('upsert'); u.add_argument('zone'); u.add_argument('name'); u.add_argument('type'); u.add_argument('ttl'); u.add_argument('records')
    d = sub.add_parser('delete'); d.add_argument('zone'); d.add_argument('name'); d.add_argument('type')
    args = p.parse_args(argv)
    c = client_from_config(args.config)
    try:
        if args.cmd == 'zones': out = c.list_zones()
        elif args.cmd == 'zone': out = c.get_zone(args.zone)
        elif args.cmd == 'export-text':
            text, count = export_zone_text(c.get_zone(args.zone))
            out = {'zone': c.zone_name(args.zone), 'text': text, 'count': count}
        elif args.cmd == 'import-text': out = import_zone_text(c, args.zone, args.text)
        elif args.cmd == 'create-zone': out = c.create_zone(args.zone, args.kind, args.nameservers)
        elif args.cmd == 'delete-zone': out = c.delete_zone(args.zone)
        elif args.cmd == 'upsert': out = c.upsert_rrset(args.zone, args.name, args.type, args.ttl, [x.strip() for x in args.records.split('\n') if x.strip()])
        elif args.cmd == 'delete': out = c.delete_rrset(args.zone, args.name, args.type)
        print(json.dumps(out if out is not None else {'ok': True}))
    except Exception as e:
        print(json.dumps({'error': str(e)})); return 1
    return 0
if __name__ == '__main__':
    raise SystemExit(main())
