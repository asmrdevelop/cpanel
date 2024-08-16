<?php

/**
 +-----------------------------------------------------------------------+
 |                                                                       |
 | cpanel - scripts/roundcube_vcf_import   Copyright 2022 cPanel, L.L.C. |
 |                                                  All rights reserved. |
 | copyright@cpanel.net                               https://cpanel.net |
 | This code is subject to the cPanel license.                           |
 | Unauthorized copying is prohibited.                                   |
 |                                                                       |
 +-----------------------------------------------------------------------+
*/

// full path to the data directory
$config['cpanel_data_dir'] = getenv('HOME'). '/.cpanel/vcards/';

// Place a "touch" file in $config['cpanel_data_dir'], preventing the plugin from
// running again if the file exits.
$config['cpanel_run_once'] = true;

// whether or not to check for duplicate addresses - if used with the
// cpanel_group_name option duplicates will be added to new groups 
$config['cpanel_unique'] = false;

// optional new group name for imported contacts - set to false to disable
$config['cpanel_group_name'] = 'Imported Contacts';

// log level 0 to disable, 1 for errors only, 2 for verbose
$config['cpanel_log_level'] = 2;

// file charset - e.g. 'EUC-JP'. Leave empty for ASCII.
$config['cpanel_file_charset'] = '';
