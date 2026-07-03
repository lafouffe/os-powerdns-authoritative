<?php

namespace OPNsense\PowerDNS;

use OPNsense\Base\IndexController;

class TextController extends IndexController
{
    public function indexAction()
    {
        $this->view->pick('OPNsense/PowerDNS/text');
    }
}
