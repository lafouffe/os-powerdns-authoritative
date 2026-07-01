#!/usr/local/bin/python3
import argparse
import json
import re
import secrets
import time
import xml.etree.ElementTree as ET
from pathlib import Path

CONF_XML = '/conf/config.xml'
BOOL_TRUE = {'1', 'true', 'yes', 'on', 'Y', 'y'}
MANAGED_PREFIX = 'os-powerdns-authoritative auto DNS'


def is_true(value):
    return str(value or '').strip() in BOOL_TRUE


def split_list(value):
    if not value:
        return []
    return [x.strip() for x in re.split(r'[,\s]+', str(value)) if x.strip()]


def get_powerdns_node(root):
    node = root.find('./OPNsense/PowerDNS')
    if node is None:
        opnsense = root.find('./OPNsense')
        if opnsense is None:
            opnsense = ET.SubElement(root, 'OPNsense')
        node = ET.SubElement(opnsense, 'PowerDNS')
    return node


def child(node, tag):
    item = node.find(tag)
    if item is None:
        item = ET.SubElement(node, tag)
    return item


def find_or_create_filter(root):
    flt = root.find('./filter')
    if flt is None:
        flt = ET.SubElement(root, 'filter')
    return flt


def rule_matches(rule, interface, protocol, port):
    return (
        (rule.findtext('type') or '').strip() == 'pass' and
        (rule.findtext('interface') or '').strip() == interface and
        (rule.findtext('protocol') or '').strip().lower() == protocol and
        (rule.findtext('destination/network') or '').strip() == interface + 'ip' and
        (rule.findtext('destination/port') or '').strip() == str(port)
    )


def add_dns_rule(filter_node, interface, protocol, port):
    for rule in filter_node.findall('rule'):
        if rule_matches(rule, interface, protocol, port):
            return False
    now = str(int(time.time()))
    rule = ET.SubElement(filter_node, 'rule')
    ET.SubElement(rule, 'type').text = 'pass'
    ET.SubElement(rule, 'interface').text = interface
    ET.SubElement(rule, 'ipprotocol').text = 'inet'
    ET.SubElement(rule, 'statetype').text = 'keep state'
    ET.SubElement(rule, 'direction').text = 'in'
    ET.SubElement(rule, 'quick').text = '1'
    ET.SubElement(rule, 'protocol').text = protocol
    source = ET.SubElement(rule, 'source')
    ET.SubElement(source, 'any').text = '1'
    destination = ET.SubElement(rule, 'destination')
    ET.SubElement(destination, 'network').text = interface + 'ip'
    ET.SubElement(destination, 'port').text = str(port)
    ET.SubElement(rule, 'descr').text = f'{MANAGED_PREFIX} {interface.upper()} {protocol.upper()} {port}'
    for tag in ('created', 'updated'):
        meta = ET.SubElement(rule, tag)
        ET.SubElement(meta, 'username').text = 'os-powerdns-authoritative'
        ET.SubElement(meta, 'time').text = now
        ET.SubElement(meta, 'description').text = 'Allow DNS queries to local PowerDNS authoritative service'
    return True


def apply_config(path=CONF_XML):
    path = Path(path)
    tree = ET.parse(path)
    root = tree.getroot()
    pdns = get_powerdns_node(root)

    changed = {
        'api_key_generated': False,
        'firewall_rules_added': False,
        'firewall_rule_count_added': 0,
    }

    enabled = is_true(pdns.findtext('enabled'))
    api_enabled = is_true(pdns.findtext('api') if pdns.find('api') is not None else '1')

    if enabled and api_enabled and not (pdns.findtext('api_key') or '').strip():
        child(pdns, 'api_key').text = secrets.token_urlsafe(32)
        changed['api_key_generated'] = True

    if enabled:
        listen_interfaces = split_list(pdns.findtext('listen_interfaces'))
        port = (pdns.findtext('local_port') or '53').strip() or '53'
        if listen_interfaces:
            flt = find_or_create_filter(root)
            for interface in listen_interfaces:
                for proto in ('tcp', 'udp'):
                    if add_dns_rule(flt, interface, proto, port):
                        changed['firewall_rules_added'] = True
                        changed['firewall_rule_count_added'] += 1

    if changed['api_key_generated'] or changed['firewall_rules_added']:
        ET.indent(root, space='  ')
        tree.write(path, encoding='utf-8', xml_declaration=True)
    return changed


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', default=CONF_XML)
    args = parser.parse_args(argv)
    print(json.dumps(apply_config(args.config)))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
