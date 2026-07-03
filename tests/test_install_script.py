import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INSTALL = ROOT / 'scripts/install-powerdns-opnsense.sh'
README = ROOT / 'README.md'

class InstallScriptTest(unittest.TestCase):
    def test_powerdns_install_is_minimal_first_and_ports_are_opt_in(self):
        script = INSTALL.read_text()
        bootstrap = (ROOT / 'scripts/bootstrap-opnsense.sh').read_text()
        self.assertIn('INSTALL_POWERDNS="${INSTALL_POWERDNS:-auto}"', script)
        self.assertIn('INSTALL_POWERDNS="${INSTALL_POWERDNS:-auto}"', bootstrap)
        self.assertIn('INSTALL_POWERDNS="$INSTALL_POWERDNS" sh', bootstrap)
        self.assertIn('TRY_PKG="${TRY_PKG:-yes}"', script)
        self.assertIn('PORTS_FETCH="${PORTS_FETCH:-no}"', script)
        self.assertIn('pkg install -y powerdns', script)
        self.assertIn('INSTALL_POWERDNS=ports PORTS_FETCH=yes', script)
        self.assertIn('opnsense-code ports', script)
        self.assertIn('make -C "$PDNS_PORT_DIR"', script)
        self.assertNotIn('PORTS_FETCH="${PORTS_FETCH:-yes}"', script)

    def test_readme_mentions_minimal_first_install(self):
        readme = README.read_text().lower()
        self.assertIn('minimal-first', readme)
        self.assertIn('no longer fetches/builds the full opnsense ports tree automatically', readme)
        self.assertIn('install_powerdns=ports ports_fetch=yes', readme)

if __name__ == '__main__':
    unittest.main()
