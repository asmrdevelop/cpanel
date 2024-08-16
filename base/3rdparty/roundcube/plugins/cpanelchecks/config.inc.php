<?php

/**
 +-----------------------------------------------------------------------+
 |                                                                       |
 | cpanel - plugins/cpanelchecks           Copyright 2023 cPanel, L.L.C. |
 |                                                  All rights reserved. |
 | copyright@cpanel.net                               https://cpanel.net |
 | This code is subject to the cPanel license.                           |
 | Unauthorized copying is prohibited.                                   |
 |                                                                       |
 +-----------------------------------------------------------------------+
*/

// full path to the data directory
$config['cpanel_data_dir'] = getenv('HOME'). '/.cpanel/';

// Place a "touch" file in $config['cpanel_data_dir'], preventing the plugin
// from running again if the file exits.
$config['cpanel_run_once'] = false;

// log level 0 to disable, 1 for errors only, 2 for verbose
$config['cpanel_log_level'] = 1;
