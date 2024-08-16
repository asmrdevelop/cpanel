package Cpanel::BandwidthDB::Remove;

# cpanel - Cpanel/BandwidthDB/Remove.pm              Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Autodie                      ();
use Cpanel::BandwidthDB::Base            ();
use Cpanel::Validate::FilesystemNodeName ();

=encoding utf-8

=head1 NAME

Cpanel::BandwidthDB::Remove - Remove bandwidth databases.

=head1 SYNOPSIS

    use Cpanel::BandwidthDB::Remove;

    Cpanel::BandwidthDB::Remove::remove_database_for_user('bob');
    Cpanel::BandwidthDB::Remove::remove_corrupted_database_for_user('bob');

=cut

=head2 remove_database_for_user($user)

Deletes the bandwidth database for a user.  Will
error if the bandwidth database has already been
deleted.

=cut

sub remove_database_for_user {
    my ($username) = @_;
    Cpanel::Validate::FilesystemNodeName::validate_or_die($username);
    return Cpanel::Autodie::unlink( Cpanel::BandwidthDB::Base->_name_to_path($username) );
}

=head2 remove_corrupted_database_for_user($user)

Deletes the corrupted bandwidth database for a user.  Will
not error if the corrupted bandwidth database has already been
deleted or never existed.

=cut

sub remove_corrupted_database_for_user {
    my ($username) = @_;
    Cpanel::Validate::FilesystemNodeName::validate_or_die($username);
    return Cpanel::Autodie::unlink_if_exists( Cpanel::BandwidthDB::Base->_name_to_path($username) . '.corrupted' );
}

1;
