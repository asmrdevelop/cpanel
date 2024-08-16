package Cpanel::Database::MariaDB::MariaDB106;

# cpanel - Cpanel/Database/MariaDB/MariaDB106.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent 'Cpanel::Database::MariaDB';

use constant {
    supported           => 1,
    recommended_version => 1,
    short_version       => '106',
    item_short_version  => '10.6',
    selected_version    => 'MariaDB106',
    locale_version      => 'MariaDB 10.6',
    eol_time            => {
        start => 1625529600,
        end   => 1783296000,
    },
    features => [
        'CREATE TABLE, ALTER TABLE, RENAME TABLE, DROP TABLE, DROP DATABASE and related DDL statements are now atomic. Either the statement is fully completed, or everything is reverted to its original state.',
        'Bundled sys_schema, a collection of views, functions, and procedures to help administrators get insight into database usage.',
        'Added various new system variables and SQL syntaxes.',
    ],
    fetch_temp_users_key_field => 'User',
    daemon_name                => 'mariadbd',
    release_notes              => 'https://go.cpanel.net/more-info-maria106',
    general_upgrade_warnings   => [
        {
            'severity' => 'Normal',
            'message'  => 'MariaDB 10.6 introduced a new reserved word: OFFSET. This can no longer be used as an identifier without being quoted.',
        },
        {
            'severity' => 'Normal',
            'message'  => 'From MariaDB 10.6, tables that are of the `COMPRESSED` row format are read-only by default. This is the first step towards removing write support and deprecating the feature. The `innodb_read_only_compressed` variable <b>must</b> be set to `OFF` in order to make the tables writable.'
        },
    ],
    config_upgrade_warnings => [],
};

sub _get_dynamic_upgrade_warnings ( $self, %opts ) {
    return ();
}

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::Database::MariaDB::MariaDB106

=head1 SYNOPSIS

The database module for MariaDB 10.6

=head1 DESCRIPTION

This module contains all code and attributes unique to MariaDB 10.6

NOTE: Please refer to Cpanel::Database::MySQL for more indepth and complete POD!!

