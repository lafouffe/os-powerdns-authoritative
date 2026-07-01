import importlib.util
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
AUTO = ROOT / 'src/opnsense/scripts/OPNsense/PowerDNS/autoconfigure.py'

class AutoconfigureTest(unittest.TestCase):
    def load_module(self):
        spec = importlib.util.spec_from_file_location('autoconfigure', AUTO)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod

    def write_xml(self, xml):
        f = tempfile.NamedTemporaryFile('w+', delete=False)
        f.write(xml)
        f.close()
        return f.name

    def test_generates_api_key_when_enabled_and_empty(self):
        mod = self.load_module()
        path = self.write_xml('''<opnsense><OPNsense><PowerDNS><enabled>1</enabled><api>1</api><api_key></api_key><listen_interfaces></listen_interfaces><local_port>53</local_port></PowerDNS></OPNsense></opnsense>''')
        with mock.patch.object(mod.secrets, 'token_urlsafe', return_value='generated-token'):
            changed = mod.apply_config(path)
        root = ET.parse(path).getroot()
        self.assertTrue(changed['api_key_generated'])
        self.assertEqual(root.findtext('./OPNsense/PowerDNS/api_key'), 'generated-token')

    def test_adds_tcp_udp_dns_firewall_rules_for_listen_interfaces(self):
        mod = self.load_module()
        path = self.write_xml('''<opnsense><OPNsense><PowerDNS><enabled>1</enabled><api>1</api><api_key>k</api_key><listen_interfaces>wan,lan</listen_interfaces><local_port>53</local_port></PowerDNS></OPNsense><filter></filter></opnsense>''')
        changed = mod.apply_config(path)
        root = ET.parse(path).getroot()
        rules = root.findall('./filter/rule')
        self.assertTrue(changed['firewall_rules_added'])
        self.assertEqual(len(rules), 4)
        pairs = {(r.findtext('interface'), r.findtext('protocol'), r.findtext('destination/network'), r.findtext('destination/port')) for r in rules}
        self.assertEqual(pairs, {('wan','tcp','wanip','53'), ('wan','udp','wanip','53'), ('lan','tcp','lanip','53'), ('lan','udp','lanip','53')})

    def test_firewall_rule_generation_is_idempotent(self):
        mod = self.load_module()
        path = self.write_xml('''<opnsense><OPNsense><PowerDNS><enabled>1</enabled><api>1</api><api_key>k</api_key><listen_interfaces>wan</listen_interfaces><local_port>53</local_port></PowerDNS></OPNsense><filter></filter></opnsense>''')
        first = mod.apply_config(path)
        second = mod.apply_config(path)
        root = ET.parse(path).getroot()
        self.assertEqual(len(root.findall('./filter/rule')), 2)
        self.assertTrue(first['firewall_rules_added'])
        self.assertFalse(second['firewall_rules_added'])

    def test_does_not_add_firewall_rules_when_service_disabled(self):
        mod = self.load_module()
        path = self.write_xml('''<opnsense><OPNsense><PowerDNS><enabled>0</enabled><api>1</api><api_key></api_key><listen_interfaces>wan</listen_interfaces><local_port>53</local_port></PowerDNS></OPNsense><filter></filter></opnsense>''')
        changed = mod.apply_config(path)
        root = ET.parse(path).getroot()
        self.assertEqual(len(root.findall('./filter/rule')), 0)
        self.assertFalse(changed['api_key_generated'])
        self.assertFalse(changed['firewall_rules_added'])

if __name__ == '__main__':
    unittest.main()
