package Cpanel::Database::MariaDB::MariaDB1011;

#                                      Copyright 2024 WebPros International, LLC
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited.

use cPstrict;

use parent 'Cpanel::Database::MariaDB';

use constant {
    experimental        => 1,
    supported           => 1,
    recommended_version => 0,
    short_version       => '1011',
    item_short_version  => '10.11',
    selected_version    => 'MariaDB1011',
    locale_version      => 'MariaDB 10.11',
    eol_time            => {
        start => 1676505600,
        end   => 1832975999,
    },
    features => [
        'Added the ability to GRANT to PUBLIC.',
        'Removed READ ONLY ADMIN from the SUPER privilege.',
        'ANALYZE FORMAT=JSON now shows time spent in the query optimizer.',
        'Better performance when reading the Information Schema Parameters and Information Schema Routines tables.',
        'History modification is now possible with the system versioning setting, system_versioning_insert_history.',
        'mariadb-dump can now dump and restore historical data.',
        'innodb_write_io_threads and innodb_read_io_threads are now dynamic, and their values can be changed without restarting the server.',
        'Added various new system variables and status variables.',
    ],
    fetch_temp_users_key_field => 'User',
    daemon_name                => 'mariadbd',
    release_notes              => 'https://go.cpanel.net/more-info-maria1011',
    general_upgrade_warnings   => [
        {
            'severity' => 'Critical',
            'message'  => 'If you used a non-zlib compression algorithm in InnoDB or Mroonga before upgrading to 10.11, the status of those tables will be unreadable until you install the appropriate compression library.'
        },
    ],
    config_upgrade_warnings               => [],
    default_innodb_buffer_pool_chunk_size => 0,
    min_innodb_buffer_pool_chunk_size     => 0,
    has_public_grants                     => 1,
};

sub _get_dynamic_upgrade_warnings ( $self, %opts ) {
    return ();
}

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::Database::MariaDB::MariaDB1011

=head1 SYNOPSIS

The database module for MariaDB 10.11

=head1 DESCRIPTION

This module contains all code and attributes unique to MariaDB 10.11

NOTE: Please refer to Cpanel::Database::MySQL for more indepth and complete POD!!

