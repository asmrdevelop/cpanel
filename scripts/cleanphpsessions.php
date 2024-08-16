<?php

# cpanel - scripts/cleanphpsessions.php            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

    ini_set('error_log', '/usr/local/cpanel/logs/error_log');

    $user = $argv[1];
    $day  = time() - 86400;
    $dbh  = sqlite_open("/var/cpanel/userhomes/$user/sessions/phpsess.sdb" );

    sqlite_query($dbh, "DELETE FROM session_data WHERE updated < $day");
    sqlite_query($dbh, "VACUUM");
    sqlite_close($dbh);
?>
