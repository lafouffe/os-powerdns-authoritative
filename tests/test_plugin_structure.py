
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'src' / 'opnsense'

class PluginStructureTest(unittest.TestCase):
    def test_required_opnsense_files_exist(self):
        required = [
            'mvc/app/models/OPNsense/PowerDNS/General.xml',
            'mvc/app/models/OPNsense/PowerDNS/General.php',
            'mvc/app/models/OPNsense/PowerDNS/Menu/Menu.xml',
            'mvc/app/models/OPNsense/PowerDNS/ACL/ACL.xml',
            'mvc/app/controllers/OPNsense/PowerDNS/GeneralController.php',
            'mvc/app/controllers/OPNsense/PowerDNS/ZonesController.php',
            'mvc/app/controllers/OPNsense/PowerDNS/TextController.php',
            'mvc/app/controllers/OPNsense/PowerDNS/Api/GeneralController.php',
            'mvc/app/controllers/OPNsense/PowerDNS/Api/ServiceController.php',
            'mvc/app/controllers/OPNsense/PowerDNS/Api/ZonesController.php',
            'mvc/app/controllers/OPNsense/PowerDNS/forms/general.xml',
            'mvc/app/views/OPNsense/PowerDNS/general.volt',
            'mvc/app/views/OPNsense/PowerDNS/zones.volt',
            'mvc/app/views/OPNsense/PowerDNS/text.volt',
            'service/conf/actions.d/actions_powerdns.conf',
            'scripts/OPNsense/PowerDNS/render_config.py',
            'scripts/OPNsense/PowerDNS/autoconfigure.py',
            'scripts/OPNsense/PowerDNS/pdns_api.py',
        ]
        missing = [p for p in required if not (SRC / p).is_file()]
        self.assertEqual(missing, [])

    def test_model_exposes_full_runtime_config_and_api_fields(self):
        xml = (SRC / 'mvc/app/models/OPNsense/PowerDNS/General.xml').read_text()
        for field in [
            'enabled','launch','gsqlite3_database','listen_interfaces','local_address','local_port',
            'setuid','setgid','loglevel','webserver','webserver_address',
            'webserver_port','webserver_allow_from','api','api_key','custom_options'
        ]:
            self.assertRegex(xml, rf'<{field}\b')

    def test_readme_has_no_unrelated_acme_references(self):
        readme = (ROOT / 'README.md').read_text().lower()
        for forbidden in ['letsencrypt', "let's encrypt", 'acme', 'lego']:
            self.assertNotIn(forbidden, readme)

    def test_zoraxy_is_not_part_of_plugin_scope(self):
        combined = '\n'.join(p.read_text(errors='ignore') for p in SRC.rglob('*') if p.is_file())
        self.assertNotRegex(combined.lower(), r'zoraxy|lego')

    def test_service_actions_cover_config_and_lifecycle(self):
        actions = (SRC / 'service/conf/actions.d/actions_powerdns.conf').read_text()
        for action in ['autoconfigure','render','checkconfig','start','stop','restart','status','reload','backupdb','filterreload','zones','zone','createzone','deletezone','upsert','delete','exporttext','importtext']:
            self.assertIn(f'[{action}]', actions)

    def test_zones_view_has_basic_record_editor(self):
        view = (SRC / 'mvc/app/views/OPNsense/PowerDNS/zones.volt').read_text()
        for needle in ['pdns-records-table', 'addZoneBtn', 'deleteZoneBtn', 'dialogZone', 'zoneName', 'zoneKind', 'saveZone', 'addRecordBtn', 'addRecordFooterBtn', 'dialogRecord', 'recordZone', 'recordName', 'recordType', 'recordTtl', 'recordValues', 'saveRecord', 'deleteRecord']:
            self.assertIn(needle, view)
        self.assertIn('table table-condensed table-hover table-striped', view)
        self.assertIn('fa fa-plus', view)
        self.assertIn('fa fa-fw fa-pencil', view)
        self.assertIn('fa fa-fw fa-trash-o', view)

    def test_general_view_uses_native_general_endpoint_and_has_zone_link(self):
        view = (SRC / 'mvc/app/views/OPNsense/PowerDNS/general.volt').read_text()
        self.assertIn('/api/powerdns/general/get', view)
        self.assertIn('/api/powerdns/general/set', view)
        self.assertIn('frm_general_settings', view)
        self.assertNotIn('frm_powerdns_settings', view)
        self.assertIn('/ui/powerdns/zones/index', view)
        self.assertIn('/ui/powerdns/text/index', view)
        self.assertIn('btn-toolbar', view)
        self.assertIn('fa fa-fw fa-play', view)
        self.assertIn('fa fa-fw fa-repeat', view)
        self.assertIn('fa fa-fw fa-stop', view)
        self.assertIn('serviceStatusText', view)
        form = (SRC / 'mvc/app/controllers/OPNsense/PowerDNS/forms/general.xml').read_text()
        self.assertIn('general.enabled', form)
        self.assertIn('<type>text</type><help>Stored in OPNsense config; visible here', form)
        self.assertNotIn('powerdns.enabled', form)

    def test_text_edit_view_and_api_are_wired(self):
        view = (SRC / 'mvc/app/views/OPNsense/PowerDNS/text.volt').read_text()
        api = (SRC / 'mvc/app/controllers/OPNsense/PowerDNS/Api/ZonesController.php').read_text()
        menu = (SRC / 'mvc/app/models/OPNsense/PowerDNS/Menu/Menu.xml').read_text()
        script = (SRC / 'scripts/OPNsense/PowerDNS/pdns_api.py').read_text()
        for needle in ['zoneTextEditor', 'exportText', 'importText', 'Apply text', '/ui/powerdns/text/index']:
            self.assertIn(needle, view)
        self.assertIn('exportTextAction', api)
        self.assertIn('importTextAction', api)
        self.assertIn('VisibleName="Text edit"', menu)
        self.assertIn('export-text', script)
        self.assertIn('import-text', script)

if __name__ == '__main__':
    unittest.main()
