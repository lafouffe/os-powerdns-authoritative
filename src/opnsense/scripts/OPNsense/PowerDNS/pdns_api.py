#!/usr/local/bin/python3
import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
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
    def list_zones(self):
        return self.request('GET', f'/servers/{self.server}/zones')
    def get_zone(self, zone):
        zone = zone if zone.endswith('.') else zone + '.'
        return self.request('GET', f'/servers/{self.server}/zones/{urllib.parse.quote(zone)}')
    def upsert_rrset(self, zone, name, rtype, ttl, records):
        zone = zone if zone.endswith('.') else zone + '.'
        name = name if name.endswith('.') else name + '.'
        rrset = {'name': name, 'type': rtype.upper(), 'ttl': int(ttl), 'changetype': 'REPLACE',
                 'records': [{'content': r, 'disabled': False} for r in records]}
        return self.request('PATCH', f'/servers/{self.server}/zones/{urllib.parse.quote(zone)}', {'rrsets':[rrset]})
    def delete_rrset(self, zone, name, rtype):
        zone = zone if zone.endswith('.') else zone + '.'
        name = name if name.endswith('.') else name + '.'
        rrset = {'name': name, 'type': rtype.upper(), 'changetype': 'DELETE', 'records': []}
        return self.request('PATCH', f'/servers/{self.server}/zones/{urllib.parse.quote(zone)}', {'rrsets':[rrset]})

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
    u = sub.add_parser('upsert'); u.add_argument('zone'); u.add_argument('name'); u.add_argument('type'); u.add_argument('ttl'); u.add_argument('records')
    d = sub.add_parser('delete'); d.add_argument('zone'); d.add_argument('name'); d.add_argument('type')
    args = p.parse_args(argv)
    c = client_from_config(args.config)
    try:
        if args.cmd == 'zones': out = c.list_zones()
        elif args.cmd == 'zone': out = c.get_zone(args.zone)
        elif args.cmd == 'upsert': out = c.upsert_rrset(args.zone, args.name, args.type, args.ttl, [x.strip() for x in args.records.split('\n') if x.strip()])
        elif args.cmd == 'delete': out = c.delete_rrset(args.zone, args.name, args.type)
        print(json.dumps(out if out is not None else {'ok': True}))
    except Exception as e:
        print(json.dumps({'error': str(e)})); return 1
    return 0
if __name__ == '__main__':
    raise SystemExit(main())
