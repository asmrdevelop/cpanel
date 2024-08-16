package Cpanel::UserDatastore;

# cpanel - Cpanel/UserDatastore.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::UserDatastore

=head1 SYNOPSIS

    Cpanel::UserDatastore::get_path('harry');

=head1 DESCRIPTION

This module implements logic to fetch the system’s
per-user administrative datastore path. This datastore:

=over

=item * … is read-accessible ONLY by the user and root

=item * … is writable ONLY by root

=item * … can safely be assumed not to be NFS-mounted

=item * … is B<NOT> backed up in account archives

=back

For logic to initialize this datastore, see
L<Cpanel::UserDatastore::Init>.

=cut

#----------------------------------------------------------------------

use Cpanel::DatastoreDir ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $dirpath = get_path( $USERNAME )

Returns the specific datastore directory for $USERNAME.

=cut

sub get_path ($username) {
    if ( !length $username ) {
        require Carp;
        Carp::croak('No username given!');
    }

    return Cpanel::DatastoreDir::PATH() . "/$username";
}

1;
