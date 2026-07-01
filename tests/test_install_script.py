import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INSTALL = ROOT / 'scripts/install-powerdns-opnsense.sh'
README = ROOT / 'README.md'

class InstallScriptTest(unittest.TestCase):
    def test_powerdns_is_installed_from_opnsense_ports_not_pkg(self):
        script = INSTALL.read_text()
        self.assertNotIn('pkg install -y powerdns', script)
        self.assertIn('opnsense-code ports', script)
        self.assertIn('/usr/ports/dns/powerdns', script)
        self.assertIn('make -C "$PDNS_PORT_DIR"', script)

    def test_readme_mentions_ports_based_powerdns_install(self):
        readme = README.read_text().lower()
        self.assertIn('powerdns is installed from the opnsense ports tree', readme)

if __name__ == '__main__':
    unittest.main()
