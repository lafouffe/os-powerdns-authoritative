<?php

namespace OPNsense\PowerDNS;

use OPNsense\Base\IndexController;

class GeneralController extends IndexController
{
    public function indexAction()
    {
        $this->view->pick('OPNsense/PowerDNS/general');
        $this->view->generalForm = $this->getForm('general');
    }
}
