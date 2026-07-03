import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INSTALL = ROOT / 'scripts/install-powerdns-opnsense.sh'
BOOTSTRAP = ROOT / 'scripts/bootstrap-opnsense.sh'
BUILD_AIO = ROOT / 'scripts/build-all-in-one-pkg.sh'
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

    def test_bootstrap_defaults_to_all_in_one_pkg(self):
        bootstrap = BOOTSTRAP.read_text()
        self.assertIn('VERSION="${VERSION:-v0.1.10}"', bootstrap)
        self.assertIn('INSTALL_METHOD="${INSTALL_METHOD:-all-in-one}"', bootstrap)
        self.assertIn('ALL_IN_ONE_PKG_URL=', bootstrap)
        self.assertIn('os-powerdns-authoritative-all-in-one-${VERSION_NUM}.pkg', bootstrap)
        self.assertIn('pkg add -f "$WORKDIR/os-powerdns-authoritative-all-in-one.pkg"', bootstrap)
        self.assertIn('pkg info -e os-powerdns-authoritative', bootstrap)
        self.assertIn('pkg delete -y os-powerdns-authoritative', bootstrap)
        self.assertIn('INSTALL_METHOD=split', bootstrap)
        self.assertIn('INSTALL_METHOD=archive', bootstrap)

    def test_release_build_scripts_exist_and_create_expected_assets(self):
        aio = BUILD_AIO.read_text()
        plugin = BUILD_PLUGIN.read_text()
        bundle = BUILD_BUNDLE.read_text()
        self.assertIn('pkg create', aio)
        self.assertIn('os-powerdns-authoritative-all-in-one', aio)
        self.assertIn('embedded-packages', aio)
        self.assertIn('run-all-in-one-install.sh', aio)
        self.assertIn('/var/log/os-powerdns-authoritative-install.log', aio)
        self.assertIn('daemon -p /var/run/os-powerdns-authoritative-install.pid', aio)
        self.assertIn('pkg add "$file"', aio)
        self.assertIn('Skipping ${base}; package ${pkgname} is already installed', aio)
        self.assertIn('ENABLE_SERVICE=yes INSTALL_POWERDNS=no', aio)
        self.assertIn('pkg create', plugin)
        self.assertIn('final="$OUTDIR/${PKG_NAME}-${VERSION}.pkg"', plugin)
        self.assertIn('install-powerdns-opnsense.sh', plugin)
        self.assertIn('pkg create -o "$WORKDIR/packages"', bundle)
        self.assertIn('powerdns-binary-bundle-OPNsense-26.1-amd64-${VERSION}.tar.gz', bundle)
        self.assertIn('install-bundled-powerdns.sh', bundle)

    def test_readme_mentions_all_in_one_and_minimal_first_install(self):
        readme = README.read_text().lower()
        self.assertIn('one-file all-in-one freebsd/opnsense `.pkg`', readme)
        self.assertIn('no external pkg repository required', readme)
        self.assertIn('no ports tree fetch/build required', readme)
        self.assertIn('/var/log/os-powerdns-authoritative-install.log', readme)
        self.assertIn('install_powerdns=ports ports_fetch=yes', readme)

if __name__ == '__main__':
    unittest.main()
