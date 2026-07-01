<?php

namespace OPNsense\PowerDNS\Api;

use OPNsense\Base\ApiControllerBase;

class ServiceController extends ApiControllerBase
{
    private function configctl($action)
    {
        $backend = new \OPNsense\Core\Backend();
        return array('response' => trim($backend->configdRun('powerdns ' . $action)));
    }

    public function statusAction() { return $this->configctl('status'); }
    public function startAction() { return $this->configctl('start'); }
    public function stopAction() { return $this->configctl('stop'); }
    public function restartAction() { return $this->configctl('restart'); }
    public function reloadAction() { return $this->configctl('reload'); }
    public function reconfigureAction()
    {
        $backend = new \OPNsense\Core\Backend();
        $auto = trim($backend->configdRun('powerdns autoconfigure'));
        $render = trim($backend->configdRun('powerdns render'));
        $check = trim($backend->configdRun('powerdns checkconfig'));
        $filter = trim($backend->configdRun('filter reload'));
        $restart = trim($backend->configdRun('powerdns restart'));
        return array('autoconfigure' => $auto, 'render' => $render, 'checkconfig' => $check, 'filter' => $filter, 'restart' => $restart);
    }
    public function backupdbAction() { return $this->configctl('backupdb'); }
}
