package Cpanel::DB::Map::Path;

# cpanel - Cpanel/DB/Map/Path.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::ConfigFiles                  ();
use Cpanel::Validate::FilesystemNodeName ();

sub data_file_for_username {
    my ($cpuser) = @_;

    Cpanel::Validate::FilesystemNodeName::validate_or_die($cpuser);

    return "$Cpanel::ConfigFiles::DATABASES_INFO_DIR/$cpuser.json";
}

1;
