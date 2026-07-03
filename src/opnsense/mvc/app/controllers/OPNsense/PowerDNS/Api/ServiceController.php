<?php

namespace OPNsense\PowerDNS\Api;

use OPNsense\Base\ApiMutableServiceControllerBase;
use OPNsense\PowerDNS\General;

class ServiceController extends ApiMutableServiceControllerBase
{
    protected static $internalServiceClass = '\\OPNsense\\PowerDNS\\General';
    protected static $internalServiceTemplate = null;
    protected static $internalServiceEnabled = 'enabled';
    protected static $internalServiceName = 'powerdns';

    protected function reconfigureForceRestart()
    {
        return 1;
    }

    protected function serviceEnabled()
    {
        return (string)(new General())->enabled == '1';
    }

    public function reconfigureAction()
    {
        if ($this->request->isPost()) {
            $backend = new \OPNsense\Core\Backend();
            $auto = trim($backend->configdRun('powerdns autoconfigure'));
            $render = trim($backend->configdRun('powerdns render'));
            $check = trim($backend->configdRun('powerdns checkconfig'));
            $filter = trim($backend->configdRun('filter reload'));
            $restart = trim($backend->configdRun('powerdns restart'));
            return array(
                'status' => 'ok',
                'autoconfigure' => $auto,
                'render' => $render,
                'checkconfig' => $check,
                'filter' => $filter,
                'restart' => $restart
            );
        }
        return array('status' => 'failed');
    }

    public function reloadAction()
    {
        if ($this->request->isPost()) {
            $backend = new \OPNsense\Core\Backend();
            return array('response' => trim($backend->configdRun('powerdns reload')));
        }
        return array('response' => array());
    }

    public function backupdbAction()
    {
        if ($this->request->isPost()) {
            $backend = new \OPNsense\Core\Backend();
            return array('response' => trim($backend->configdRun('powerdns backupdb')));
        }
        return array('response' => array());
    }
}
