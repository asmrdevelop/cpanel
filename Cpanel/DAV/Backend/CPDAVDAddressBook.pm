
# cpanel - Cpanel/DAV/Backend/CPDAVDAddressBook.pm Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
package Cpanel::DAV::Backend::CPDAVDAddressBook;

use cPstrict;

use parent qw(Cpanel::DAV::Backend::CPDAVDCollectionBase);

sub _collection_type        { return 'VADDRESSBOOK' }
sub _collection_type_pretty { return 'address book' }

=head1 NAME

Cpanel::DAV::Backend::CPDAVDAddressBook

=head1 DESCRIPTION

Cpanel::DAV::Backend::CPDAVDAddressBook

A backend class that can be loaded to create/update/delete address books

=cut

1;
