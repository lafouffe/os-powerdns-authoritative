<?php

namespace OPNsense\PowerDNS\Api;

use OPNsense\Base\ApiControllerBase;

class ZonesController extends ApiControllerBase
{
    private function runJson($args)
    {
        $backend = new \OPNsense\Core\Backend();
        $cmd = 'powerdns ' . implode(' ', array_map('escapeshellarg', $args));
        $out = trim($backend->configdRun($cmd));
        $decoded = json_decode($out, true);
        return $decoded === null ? array('error' => $out) : $decoded;
    }

    public function searchAction()
    {
        return $this->runJson(array('zones'));
    }

    public function getAction($zone = null)
    {
        return $this->runJson(array('zone', $zone));
    }

    public function setRecordAction()
    {
        $zone = $this->request->getPost('zone');
        $name = $this->request->getPost('name');
        $type = $this->request->getPost('type');
        $ttl = $this->request->getPost('ttl');
        $records = $this->request->getPost('records');
        return $this->runJson(array('upsert', $zone, $name, $type, $ttl, $records));
    }

    public function deleteRecordAction()
    {
        $zone = $this->request->getPost('zone');
        $name = $this->request->getPost('name');
        $type = $this->request->getPost('type');
        return $this->runJson(array('delete', $zone, $name, $type));
    }
}
