package Cpanel::DatastoreDir;

# cpanel - Cpanel/DatastoreDir.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::DatastoreDir

=head1 SYNOPSIS

    my $path = Cpanel::DatastoreDir::PATH();

=head1 DESCRIPTION

This module provides a function that gives the path for the administrative
datastore, historically F</var/cpanel/datastore>. This datastore:

=over

=item * Is world-accessible

=item * Is enumerable B<ONLY> by root

=item * Is writable B<ONLY> by root

=back

See L<Cpanel::DatastoreDir::Init> for corresponding initialization logic.

=cut

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 PATH()

Returns the datastore path, which is a directory.

=cut

# This is a function rather than a constant so that it can be mocked
# in tests.
sub PATH {
    return '/var/cpanel/datastore';
}

1;
