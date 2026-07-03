#!/usr/local/bin/python3
import argparse
import os
import re
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

CONF_XML = '/conf/config.xml'
PDNS_CONF = '/usr/local/etc/pdns/pdns.conf'
BOOL_TRUE = {'1','true','yes','on','Y','y'}
BLOCKED_EXTRA = {'include-dir','include-file','config-dir','config-name'}
DEFAULTS = {
    'enabled':'1','launch':'gsqlite3','gsqlite3_database':'/var/db/pdns/pdns.sqlite3',
    'listen_interfaces':'','local_address':'','local_port':'53',
    'webserver':'1','webserver_address':'127.0.0.1','webserver_port':'8081',
    'webserver_allow_from':'127.0.0.1,::1','api':'1','api_key':'','custom_options':''
}

FIXED_RUNTIME = {
    'setuid': 'pdns',
    'setgid': 'pdns',
    'loglevel': '4',
}

def yesno(value):
    return 'yes' if str(value).strip() in BOOL_TRUE else 'no'

def text_or_join(node):
    if node.text and node.text.strip():
        return node.text.strip()
    values = []
    for child in list(node):
        if child.text and child.text.strip():
            values.append(child.text.strip())
    return ','.join(values)

def load_config_xml(path=CONF_XML):
    cfg = DEFAULTS.copy()
    root = ET.parse(path).getroot()
    node = root.find('./OPNsense/PowerDNS')
    if node is None:
        node = root.find('.//PowerDNS')
    if node is None:
        return cfg
    for child in list(node):
        cfg[child.tag] = text_or_join(child)
    return cfg

def validate_extra(line):
    raw = line.strip()
    if not raw or raw.startswith('#'):
        return raw
    if '=' not in raw:
        raise ValueError('custom option must be key=value: %s' % raw)
    key = raw.split('=',1)[0].strip()
    if not re.match(r'^[A-Za-z0-9_.-]+$', key):
        raise ValueError('invalid custom option key: %s' % key)
    if key in BLOCKED_EXTRA:
        raise ValueError('blocked custom option: %s' % key)
    return raw

def split_list(value):
    if not value:
        return []
    return [x.strip() for x in re.split(r'[,\s]+', str(value)) if x.strip()]

def interface_device_map(config_path=CONF_XML):
    mapping = {}
    try:
        root = ET.parse(config_path).getroot()
    except Exception:
        return mapping
    interfaces = root.find('./interfaces')
    if interfaces is None:
        return mapping
    for logical in list(interfaces):
        ifname = logical.findtext('if') or logical.tag
        mapping[logical.tag] = ifname
    return mapping

def ifconfig_ipv4(device):
    if not device:
        return []
    try:
        out = subprocess.run(['/sbin/ifconfig', device], capture_output=True, text=True, timeout=5).stdout
    except Exception:
        return []
    addrs = []
    for line in out.splitlines():
        m = re.match(r'\s*inet\s+(\d+\.\d+\.\d+\.\d+)\b', line)
        if m and not m.group(1).startswith('127.'):
            addrs.append(m.group(1))
    return addrs

def resolve_listen_addresses(cfg, config_path=CONF_XML):
    manual = ','.join(split_list(cfg.get('local_address','')))
    if manual:
        return manual
    mapping = interface_device_map(config_path)
    addrs = []
    for logical in split_list(cfg.get('listen_interfaces','')):
        device = mapping.get(logical, logical)
        for addr in ifconfig_ipv4(device):
            if addr not in addrs:
                addrs.append(addr)
    return ','.join(addrs)

def render_pdns_conf(cfg, config_path=CONF_XML):
    cfg = {**DEFAULTS, **{k: ('' if v is None else str(v)) for k, v in cfg.items()}}
    lines = [
        '# Managed by OPNsense PowerDNS Authoritative plugin',
        'launch=%s' % cfg['launch'],
    ]
    if cfg['launch'] == 'gsqlite3':
        lines.append('gsqlite3-database=%s' % cfg['gsqlite3_database'])
    listen_addresses = resolve_listen_addresses(cfg, config_path)
    if listen_addresses:
        lines.append('local-address=%s' % listen_addresses)
    lines += [
        'local-port=%s' % cfg['local_port'],
        'setuid=%s' % FIXED_RUNTIME['setuid'],
        'setgid=%s' % FIXED_RUNTIME['setgid'],
        'loglevel=%s' % FIXED_RUNTIME['loglevel'],
        '',
        'webserver=%s' % yesno(cfg['webserver']),
    ]
    if yesno(cfg['webserver']) == 'yes':
        lines += [
            'webserver-address=%s' % cfg['webserver_address'],
            'webserver-port=%s' % cfg['webserver_port'],
            'webserver-allow-from=%s' % cfg['webserver_allow_from'],
        ]
    lines += ['api=%s' % yesno(cfg['api'])]
    if yesno(cfg['api']) == 'yes':
        lines.append('api-key=%s' % cfg['api_key'])
    extras = []
    for line in cfg.get('custom_options','').splitlines():
        safe = validate_extra(line)
        if safe:
            extras.append(safe)
    if extras:
        lines.append('')
        lines.append('# Extra options from OPNsense UI')
        lines.extend(extras)
    return '\n'.join(lines).rstrip() + '\n'

def write_config(text, dest=PDNS_CONF):
    target = Path(dest)
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        backup = target.with_suffix(target.suffix + '.opnsense-plugin-bak')
        backup.write_bytes(target.read_bytes())
    target.write_text(text)
    os.chmod(target, 0o600)

if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--config', default=CONF_XML)
    ap.add_argument('--output', default=PDNS_CONF)
    ap.add_argument('--write', action='store_true')
    args = ap.parse_args()
    conf = render_pdns_conf(load_config_xml(args.config), args.config)
    if args.write:
        write_config(conf, args.output)
        print('rendered %s' % args.output)
    else:
        print(conf, end='')
