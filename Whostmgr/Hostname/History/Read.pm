package Whostmgr::Hostname::History::Read;

# cpanel - Whostmgr/Hostname/History/Read.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Hostname::History::Read

=head1 SYNOPSIS

    use Whostmgr::Hostname::History::Read ()

    my $ar = Whostmgr::Hostname::History::Read::get()

=head1 DESCRIPTION ()

This module Implements read-only logic for interacting with
the hostname history.

=cut

use Cpanel::JSON                ();
use Cpanel::LoadFile            ();
use Whostmgr::Hostname::History ();

=head1 FUNCTIONS

=head2 $ar = get()

Reads the datastore. The return value is an array reference; each
array item is a hash reference of:

=over

=item * C<old_hostname>

=item * C<timestamp> (RFC 3339 format)

=back

=cut

sub get() {
    my $path = Whostmgr::Hostname::History::file();

    my $data_ar = Cpanel::LoadFile::load_if_exists($path);

    if ($data_ar) {
        $data_ar = Cpanel::JSON::Load($data_ar);
    }

    return $data_ar || [];
}

1;
