package Cpanel::BandwidthDB::Read::Tiny;

# cpanel - Cpanel/BandwidthDB/Read/Tiny.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# This class is for instantiating a read-only object to access bandwidth DB
# data. It ONLY knows how to do that.
#
# If you want something that creates the DB if it doesn’t exist, then
# you probably want Cpanel::BandwidthDB, which contains factory functions for
# this class.
#
#----------------------------------------------------------------------

#----------------------------------------------------------------------
# NOTE:
# This class internally uses the term “moniker” as a generic term for either:
#   - a domain name
#   - the “unknown-domain” category
#
# It seems best NOT to expose this term publicly.
#----------------------------------------------------------------------

=encoding utf-8

=head1 NAME

Cpanel::BandwidthDB::Read::Tiny - Quick functions to check to see if a user has a bandwidth db

=head1 SYNOPSIS

    use Cpanel::BandwidthDB::Read::Tiny ();

    if (! Cpanel::BandwidthDB::Read::Tiny::user_has_database('bob') ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::BandwidthDB::Create');
        ....
    }

=head1 DESCRIPTION

This module exists so we can check if a user has a bandwidth database
before loading any of the other Cpanel::BandwidthDB modules that
bring in DBI and sqlite.

=cut

use strict;
use warnings;

use Cpanel::Autodie ('exists');
use Cpanel::Validate::FilesystemNodeName ();
use Cpanel::BandwidthDB::Constants       ();

#----------------------------------------------------------------------
#Static functions

=head2 user_has_database

Determine if a cPanel user has a bandwidth db.

=over 2

=item Input

=over 3

=item C<SCALAR>

    The username to check

=back

=item Output

=over 3

=item C<SCALAR>

    A truthy value if the db exists, a falsey value if it does not.

=back

=back

=cut

sub user_has_database {
    my ($username) = @_;

    Cpanel::Validate::FilesystemNodeName::validate_or_die($username);

    return Cpanel::Autodie::exists( _name_to_path($username) );
}

#NOTE: Tests call this logic directly.
sub _name_to_path {
    my ($username) = @_;

    return "$Cpanel::BandwidthDB::Constants::DIRECTORY/$username.sqlite";
}

1
