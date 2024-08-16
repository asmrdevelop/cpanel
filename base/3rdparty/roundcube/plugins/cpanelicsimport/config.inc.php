<?php

/**
 +-----------------------------------------------------------------------+
 |                                                                       |
 | cpanel - scripts/roundcube_ics_import   Copyright 2022 cPanel, L.L.C. |
 |                                                  All rights reserved. |
 | copyright@cpanel.net                               https://cpanel.net |
 | This code is subject to the cPanel license.                           |
 | Unauthorized copying is prohibited.                                   |
 |                                                                       |
 +-----------------------------------------------------------------------+
*/

// full path to the data directory
$config['cpanel_data_dir'] = getenv('HOME'). '/.cpanel/icals/';

// Place a "touch" file in $config['cpanel_data_dir'], preventing the plugin from
// running again if the file exits.
$config['cpanel_run_once'] = true;

// whether or not to check for duplicate events
$config['cpanel_unique'] = false;

// optional new calendar name for imported events - set to false to disable
$config['cpanel_cal_name'] = 'Imported Calendar';

// log level 0 to disable, 1 for errors only, 2 for verbose
$config['cpanel_log_level'] = 2;

// file charset - e.g. 'EUC-JP'. Leave empty for ASCII.
$config['cpanel_file_charset'] = '';
