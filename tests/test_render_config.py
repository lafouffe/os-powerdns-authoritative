import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
RENDER = ROOT / 'src/opnsense/scripts/OPNsense/PowerDNS/render_config.py'

class RenderConfigTest(unittest.TestCase):
    def load_module(self):
        spec = importlib.util.spec_from_file_location('render_config', RENDER)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod

    def test_render_includes_all_enabled_options_with_manual_address_override(self):
        mod = self.load_module()
        cfg = {
            'enabled':'1', 'launch':'gsqlite3', 'gsqlite3_database':'/var/db/pdns/pdns.sqlite3',
            'listen_interfaces':'wan', 'local_address':'203.0.113.10', 'local_port':'53', 'setuid':'pdns', 'setgid':'pdns',
            'loglevel':'4', 'webserver':'1', 'webserver_address':'127.0.0.1', 'webserver_port':'8081',
            'webserver_allow_from':'127.0.0.1,::1', 'api':'1', 'api_key':'example-api-key',
            'custom_options':'guardian=yes\nreceiver-threads=1'
        }
        text = mod.render_pdns_conf(cfg)
        for expected in [
            'launch=gsqlite3', 'gsqlite3-database=/var/db/pdns/pdns.sqlite3',
            'local-address=203.0.113.10', 'local-port=53', 'setuid=pdns', 'setgid=pdns',
            'loglevel=4', 'webserver=yes', 'webserver-address=127.0.0.1',
            'webserver-port=8081', 'webserver-allow-from=127.0.0.1,::1',
            'api=yes', 'api-key=example-api-key', 'guardian=yes', 'receiver-threads=1'
        ]:
            self.assertIn(expected, text)

    def test_render_resolves_selected_interfaces_when_no_manual_address(self):
        mod = self.load_module()
        xml = '''<opnsense>
          <interfaces><wan><if>igb0</if></wan><lan><if>igb1</if></lan></interfaces>
          <OPNsense><PowerDNS><listen_interfaces>wan,lan</listen_interfaces><local_address></local_address></PowerDNS></OPNsense>
        </opnsense>'''
        with tempfile.NamedTemporaryFile('w+', delete=False) as f:
            f.write(xml); path=f.name
        with mock.patch.object(mod, 'ifconfig_ipv4', side_effect=lambda dev: {'igb0':['203.0.113.10'], 'igb1':['192.0.2.1']}.get(dev, [])):
            text = mod.render_pdns_conf(mod.load_config_xml(path), path)
        self.assertIn('local-address=203.0.113.10,192.0.2.1', text)

    def test_render_omits_local_address_when_empty_and_no_interface(self):
        mod = self.load_module()
        text = mod.render_pdns_conf({'local_address':'', 'listen_interfaces':''})
        self.assertNotIn('local-address=', text)

    def test_render_rejects_unsafe_custom_options(self):
        mod = self.load_module()
        with self.assertRaises(ValueError):
            mod.render_pdns_conf({'custom_options':'bad line without equals'})
        with self.assertRaises(ValueError):
            mod.render_pdns_conf({'custom_options':'include-dir=/tmp/nope'})

    def test_parse_config_xml_extracts_powerdns_model(self):
        mod = self.load_module()
        xml = '<opnsense><OPNsense><PowerDNS><enabled>1</enabled><local_address>203.0.113.10</local_address><api_key>k</api_key></PowerDNS></OPNsense></opnsense>'
        with tempfile.NamedTemporaryFile('w+', delete=False) as f:
            f.write(xml); path=f.name
        self.assertEqual(mod.load_config_xml(path)['local_address'], '203.0.113.10')

if __name__ == '__main__':
    unittest.main()
