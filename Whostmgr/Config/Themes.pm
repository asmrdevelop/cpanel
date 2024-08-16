package Whostmgr::Config::Themes;

# cpanel - Whostmgr/Config/Themes.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our %themes_files = (
    '/var/cpanel/customizations' => {
        'special'     => "dir",
        'archive_dir' => "cpanel/ui/themes/customizations"
    },
    '/var/cpanel/activate/features/set_paperlantern_as_default' => { 'special' => "present" },
    '/var/cpanel/activate/features/paper_lantern'               => { 'special' => "present" },
);

1;
