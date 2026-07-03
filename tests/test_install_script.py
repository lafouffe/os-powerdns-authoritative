import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INSTALL = ROOT / 'scripts/install-powerdns-opnsense.sh'
BOOTSTRAP = ROOT / 'scripts/bootstrap-opnsense.sh'
BUILD_PLUGIN = ROOT / 'scripts/build-opnsense-pkg.sh'
BUILD_BUNDLE = ROOT / 'scripts/build-powerdns-binary-bundle.sh'
README = ROOT / 'README.md'

class InstallScriptTest(unittest.TestCase):
    def test_powerdns_install_is_minimal_first_and_ports_are_opt_in(self):
        script = INSTALL.read_text()
        self.assertIn('INSTALL_POWERDNS="${INSTALL_POWERDNS:-auto}"', script)
        self.assertIn('TRY_PKG="${TRY_PKG:-yes}"', script)
        self.assertIn('PORTS_FETCH="${PORTS_FETCH:-no}"', script)
        self.assertIn('pkg install -y powerdns', script)
        self.assertIn('INSTALL_POWERDNS=ports PORTS_FETCH=yes', script)
        self.assertIn('opnsense-code ports', script)
        self.assertIn('make -C "$PDNS_PORT_DIR"', script)
        self.assertNotIn('PORTS_FETCH="${PORTS_FETCH:-yes}"', script)

    def test_bootstrap_defaults_to_pkg_and_binary_bundle(self):
        bootstrap = BOOTSTRAP.read_text()
        self.assertIn('VERSION="${VERSION:-v0.1.8}"', bootstrap)
        self.assertIn('INSTALL_METHOD="${INSTALL_METHOD:-pkg}"', bootstrap)
        self.assertIn('INSTALL_POWERDNS="${INSTALL_POWERDNS:-binary}"', bootstrap)
        self.assertIn('PLUGIN_PKG_URL=', bootstrap)
        self.assertIn('BINARY_BUNDLE_URL=', bootstrap)
        self.assertIn('pkg add -f "$WORKDIR/os-powerdns-authoritative.pkg"', bootstrap)
        self.assertIn('install_powerdns_binary_bundle', bootstrap)
        self.assertIn('INSTALL_METHOD=archive', bootstrap)

    def test_release_build_scripts_exist_and_create_expected_assets(self):
        plugin = BUILD_PLUGIN.read_text()
        bundle = BUILD_BUNDLE.read_text()
        self.assertIn('pkg create', plugin)
        self.assertIn('final="$OUTDIR/${PKG_NAME}-${VERSION}.pkg"', plugin)
        self.assertIn('install-powerdns-opnsense.sh', plugin)
        self.assertIn('pkg create -o "$WORKDIR/packages"', bundle)
        self.assertIn('powerdns-binary-bundle-OPNsense-26.1-amd64-${VERSION}.tar.gz', bundle)
        self.assertIn('install-bundled-powerdns.sh', bundle)

    def test_readme_mentions_pkg_and_minimal_first_install(self):
        readme = README.read_text().lower()
        self.assertIn('freebsd/opnsense `.pkg` release asset', readme)
        self.assertIn('powerdns binary bundle', readme)
        self.assertIn('no longer fetches/builds the full opnsense ports tree automatically', readme)
        self.assertIn('install_powerdns=ports ports_fetch=yes', readme)

if __name__ == '__main__':
    unittest.main()
