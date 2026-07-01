import importlib.util
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
AUTO = ROOT / 'src/opnsense/scripts/OPNsense/PowerDNS/autoconfigure.py'
ACTIONS = ROOT / 'src/opnsense/service/conf/actions.d/actions_powerdns.conf'

class ServiceEnableTest(unittest.TestCase):
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

    def test_autoconfigure_enables_rc_service_when_plugin_enabled(self):
        mod = self.load_module()
        path = self.write_xml('<opnsense><OPNsense><PowerDNS><enabled>1</enabled><api>0</api><listen_interfaces></listen_interfaces></PowerDNS></OPNsense></opnsense>')
        with mock.patch.object(mod.subprocess, 'run') as run:
            changed = mod.apply_config(path)
        run.assert_called_with(['sysrc', 'pdns_enable=YES'], capture_output=True, text=True, timeout=10)
        self.assertTrue(changed['service_enabled'])

    def test_service_actions_use_one_variants_to_avoid_rc_disabled_failure(self):
        actions = ACTIONS.read_text()
        self.assertIn('command:/usr/local/etc/rc.d/pdns onestart', actions)
        self.assertIn('command:/usr/local/etc/rc.d/pdns onerestart', actions)
        self.assertNotIn('command:/usr/local/etc/rc.d/pdns start\n', actions)
        self.assertNotIn('command:/usr/local/etc/rc.d/pdns restart\n', actions)

if __name__ == '__main__':
    unittest.main()
