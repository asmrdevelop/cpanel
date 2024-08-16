<?php
// Copyright 1999-2020. Plesk International GmbH. All rights reserved.

include("/usr/local/cpanel/php/cpanel.php");
$cpanel = new CPANEL();

require_once('/usr/local/cpanel/3rdparty/wp-toolkit/php-files/requirements.php');

$application = new WpToolkitApplication(
    new CpanelMainPage($cpanel)
);
$application->run();
