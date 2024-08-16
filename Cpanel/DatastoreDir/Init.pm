package Cpanel::DatastoreDir::Init;

# cpanel - Cpanel/DatastoreDir/Init.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::DatastoreDir::Init

=head1 SYNOPSIS

    my $path = Cpanel::DatastoreDir::Init::initialize();

=head1 DESCRIPTION

This module implements standard logic for creating and initializing
C<Cpanel::DatastoreDir::PATH()>.

=cut

#----------------------------------------------------------------------

use Cpanel::DatastoreDir ();
use Cpanel::Mkdir        ();

my $did_init;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $dir = initialize()

Initializes the datastore, ensuring that permissions are correct.

As a convenience, the datastore’s path (i.e., the return of
C<Cpanel::DatastoreDir::PATH()>) is returned.

=cut

sub initialize {
    my $dir = Cpanel::DatastoreDir::PATH();

    $did_init ||= do {
        Cpanel::Mkdir::ensure_directory_existence_and_mode( $dir, 0711 );
        1;
    };

    return $dir;
}

# For testing
sub _clear_init_cache () {
    $did_init = undef;

    return;
}

1;
