package Cpanel::UserDatastore::Init;

# cpanel - Cpanel/UserDatastore/Init.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::UserDatastore

=head1 SYNOPSIS

    Cpanel::UserDatastore::Init::initialize('harry');

=head1 DESCRIPTION

This module implements logic to initialize the system’s
per-user administrative datastore. This datastore:

=over

=item * … is read-accessible ONLY by the user and root

=item * … is writable ONLY by root

=item * … can safely be assumed not to be NFS-mounted

=item * … is B<NOT> backed up in account archives

=back

=cut

#----------------------------------------------------------------------

use Cpanel::Autodie            ();
use Cpanel::DatastoreDir::Init ();
use Cpanel::Mkdir              ();
use Cpanel::UserDatastore      ();

# made global to allow easy resetting
our %USERNAME_INITIALIZED;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $dirpath = initialize( $USERNAME )

Initializes the datastore directory for the given $USERNAME.

Returns the result of C<get_path()> as a convenience.

=cut

sub initialize ($username) {
    my $path = Cpanel::UserDatastore::get_path($username);

    my $needs_base_init = !%USERNAME_INITIALIZED;

    $USERNAME_INITIALIZED{$username} ||= do {
        Cpanel::DatastoreDir::Init::initialize();

        my $group = _get_group_id($username) // die "Got no group for $username!";

        Cpanel::Mkdir::ensure_directory_existence_and_mode( $path, 0750 );

        Cpanel::Autodie::chown( -1, $group, $path );

        1;
    };

    return $path;
}

#----------------------------------------------------------------------

sub _get_group_id ($username) {
    return ( ( getgrnam $username )[2] );
}

1;
