<?php

namespace OPNsense\PowerDNS;

use OPNsense\Base\IndexController;

class ZonesController extends IndexController
{
    public function indexAction()
    {
        $this->view->pick('OPNsense/PowerDNS/zones');
    }
}
