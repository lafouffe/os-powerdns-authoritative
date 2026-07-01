
import http.server
import importlib.util
import json
import threading
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CLIENT = ROOT / 'src/opnsense/scripts/OPNsense/PowerDNS/pdns_api.py'

class FakePowerDNS(http.server.BaseHTTPRequestHandler):
    requests = []
    zone = {
        'id':'example.org.', 'name':'example.org.', 'kind':'Master',
        'rrsets':[{'name':'example.org.','type':'A','ttl':300,'records':[{'content':'203.0.113.10','disabled':False}]}]
    }
    def log_message(self, *args):
        pass
    def _send(self, code, obj=None):
        self.send_response(code); self.send_header('Content-Type','application/json'); self.end_headers()
        if obj is not None: self.wfile.write(json.dumps(obj).encode())
    def do_GET(self):
        self.__class__.requests.append(('GET', self.path, self.headers.get('X-API-Key'), None))
        if self.path == '/api/v1/servers/localhost/zones':
            return self._send(200, [self.zone])
        if self.path == '/api/v1/servers/localhost/zones/example.org.':
            return self._send(200, self.zone)
        return self._send(404, {'error':'Not Found'})
    def do_PATCH(self):
        body = self.rfile.read(int(self.headers.get('Content-Length','0'))).decode()
        self.__class__.requests.append(('PATCH', self.path, self.headers.get('X-API-Key'), json.loads(body)))
        return self._send(204)
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get('Content-Length','0'))).decode()
        payload = json.loads(body)
        self.__class__.requests.append(('POST', self.path, self.headers.get('X-API-Key'), payload))
        return self._send(201, {'id': payload.get('name'), 'name': payload.get('name'), 'kind': payload.get('kind')})
    def do_DELETE(self):
        self.__class__.requests.append(('DELETE', self.path, self.headers.get('X-API-Key'), None))
        return self._send(204)

class PowerDNSApiClientTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.httpd = http.server.ThreadingHTTPServer(('127.0.0.1', 0), FakePowerDNS)
        cls.port = cls.httpd.server_port
        cls.thread = threading.Thread(target=cls.httpd.serve_forever, daemon=True)
        cls.thread.start()
    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()
    def load_module(self):
        spec = importlib.util.spec_from_file_location('pdns_api', CLIENT)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod
    def test_list_zones_uses_api_v1_and_api_key(self):
        mod = self.load_module()
        client = mod.PowerDNSClient(f'http://127.0.0.1:{self.port}', 'secret')
        zones = client.list_zones()
        self.assertEqual(zones[0]['name'], 'example.org.')
        self.assertIn(('GET','/api/v1/servers/localhost/zones','secret',None), FakePowerDNS.requests)
    def test_upsert_rrset_sends_replace_patch(self):
        mod = self.load_module()
        client = mod.PowerDNSClient(f'http://127.0.0.1:{self.port}', 'secret')
        client.upsert_rrset('example.org.', 'www.example.org.', 'A', 300, ['203.0.113.10'])
        patch = [r for r in FakePowerDNS.requests if r[0] == 'PATCH'][-1]
        self.assertEqual(patch[1], '/api/v1/servers/localhost/zones/example.org.')
        self.assertEqual(patch[3]['rrsets'][0]['changetype'], 'REPLACE')
        self.assertEqual(patch[3]['rrsets'][0]['records'][0]['content'], '203.0.113.10')
    def test_create_and_delete_zone_use_powerdns_zone_api(self):
        mod = self.load_module()
        client = mod.PowerDNSClient(f'http://127.0.0.1:{self.port}', 'secret')
        client.create_zone('new.example.org', 'Native', 'ns1.example.org.\nns2.example.org.')
        post = [r for r in FakePowerDNS.requests if r[0] == 'POST'][-1]
        self.assertEqual(post[1], '/api/v1/servers/localhost/zones')
        self.assertEqual(post[3]['name'], 'new.example.org.')
        self.assertEqual(post[3]['kind'], 'Native')
        self.assertEqual(post[3]['nameservers'], ['ns1.example.org.', 'ns2.example.org.'])
        client.delete_zone('new.example.org')
        delete = [r for r in FakePowerDNS.requests if r[0] == 'DELETE'][-1]
        self.assertEqual(delete[1], '/api/v1/servers/localhost/zones/new.example.org.')

if __name__ == '__main__':
    unittest.main()
