package Cpanel::WebCalls::Datastore::ReadAsUser;

# cpanel - Cpanel/WebCalls/Datastore/ReadAsUser.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::WebCalls::Datastore::ReadAsUser

=head1 SYNOPSIS

    my $entries_hr = Cpanel::WebCalls::Datastore::ReadAsUser::read_all();

=head1 DESCRIPTION

This module provides logic for reading the webcalls datastore as a
user. It wraps the appropriate admin function calls.

=cut

#----------------------------------------------------------------------

use Cpanel::AdminBin::Call ();
use Cpanel::LoadModule     ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $entries_hr = read_all()

Equivalent to:

    Cpanel::WebCalls::Datastore::Read->read_for_user($username)

=cut

sub read_all () {
    my $entries_hr = Cpanel::AdminBin::Call::call( 'Cpanel', 'webcalls', 'GET_ENTRIES' );

    for my $ref ( values %$entries_hr ) {
        my $entry_class = "Cpanel::WebCalls::Entry::$ref->{'type'}";
        Cpanel::LoadModule::load_perl_module($entry_class)->adopt($ref);
    }

    return $entries_hr;
}

1;
