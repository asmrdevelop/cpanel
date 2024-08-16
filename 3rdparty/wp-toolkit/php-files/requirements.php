<?php
// Copyright 1999-2020. Plesk International GmbH. All rights reserved.

require_once('/usr/local/cpanel/3rdparty/wp-toolkit/php-files/MemoryLogger.php');
MemoryLogger::getInstance()->start();
MemoryLogger::getInstance()->log('Start application');

require_once('/usr/local/cpanel/3rdparty/wp-toolkit/php-files/MainPageInterface.php');
require_once('/usr/local/cpanel/3rdparty/wp-toolkit/php-files/WpToolkitApplication.php');
require_once('/usr/local/cpanel/3rdparty/wp-toolkit/php-files/WhmAccessChecker.php');
require_once('/usr/local/cpanel/3rdparty/wp-toolkit/php-files/WhmMainPage.php');
require_once('/usr/local/cpanel/3rdparty/wp-toolkit/php-files/CpanelMainPage.php');
