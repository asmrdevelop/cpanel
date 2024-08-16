package Cpanel::Database::MariaDB::MariaDB55;

# cpanel - Cpanel/Database/MariaDB/MariaDB55.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent 'Cpanel::Database::MariaDB::MariaDB100';

use constant {
    supported                => 0,
    recommended_version      => 0,
    short_version            => '55',
    item_short_version       => '5.5',
    selected_version         => 'MariaDB55',
    locale_version           => 'MariaDB 5.5',
    general_upgrade_warnings => [],
    config_upgrade_warnings  => [],
};

1;

=encoding utf-8

=head1 NAME

Cpanel::Database::MariaDB::MariaDB55

=head1 SYNOPSIS

The database module for MariaDB 5.5

=head1 DESCRIPTION

MariaDB 5.5 is not offically supported.

This is a placeholder. Do not add code to this module.

This module will ensure people who are running MariaDB 5.5 will
at least have a functioning cPanel server.
