
# cpanel - Cpanel/ImagePrep/Task/cpstore.pm        Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
package Cpanel::ImagePrep::Task::cpstore;

use cPstrict;
use Cpanel::Market::Provider::cPStore::ProductsCache ();

use parent 'Cpanel::ImagePrep::Task';

=head1 NAME

Cpanel::ImagePrep::Task::cpstore - An implementation subclass of Cpanel::ImagePrep::Task. See parent class for interface.

=cut

sub _description {
    return <<~EOF;
        Remove the cPanel Store product cache.
        EOF
}

sub _type { return 'non-repair only' }

sub _pre ($self) {

    if ( Cpanel::Market::Provider::cPStore::ProductsCache->delete() ) {
        $self->loginfo('Removed the cPanel Store product cache.');
        return $self->PRE_POST_OK;
    }

    return $self->PRE_POST_NOT_APPLICABLE;
}

sub _post ($self) {
    return $self->PRE_POST_NOT_APPLICABLE;
}

1;
