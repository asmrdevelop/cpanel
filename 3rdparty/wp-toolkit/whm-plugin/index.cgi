#!/usr/local/cpanel/3rdparty/bin/php-cgi
<?php
// Copyright 1999-2020. Plesk International GmbH. All rights reserved.

require_once('/usr/local/cpanel/php/WHM.php');
require_once('/usr/local/cpanel/3rdparty/wp-toolkit/php-files/requirements.php');

$application = new WpToolkitApplication(
    new WhmMainPage(
        new WhmAccessChecker()
    )
);
$application->run();
