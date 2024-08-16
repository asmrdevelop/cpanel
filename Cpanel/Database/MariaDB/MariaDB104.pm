package Cpanel::Database::MariaDB::MariaDB104;

# cpanel - Cpanel/Database/MariaDB/MariaDB104.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent 'Cpanel::Database::MariaDB::MariaDB105';

use constant {
    supported                => 0,
    recommended_version      => 0,
    short_version            => '104',
    item_short_version       => '10.4',
    selected_version         => 'MariaDB104',
    locale_version           => 'MariaDB 10.4',
    general_upgrade_warnings => [],
    config_upgrade_warnings  => [],
};

1;

=encoding utf-8

=head1 NAME

Cpanel::Database::MariaDB::MariaDB104

=head1 SYNOPSIS

The database module for MariaDB 10.4

=head1 DESCRIPTION

MariaDB 10.4 is not offically supported.

This is a placeholder. Do not add code to this module.

This module will ensure people who are running MariaDB 10.4 will
at least have a functioning cPanel server.
