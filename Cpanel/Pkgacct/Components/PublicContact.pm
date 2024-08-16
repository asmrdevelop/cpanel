package Cpanel::Pkgacct::Components::PublicContact;

# cpanel - Cpanel/Pkgacct/Components/PublicContact.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Pkgacct::Components::PublicContact

=head1 SYNOPSIS

    my $obj = Cpanel::Pkgacct->new( ... );
    $obj->perform_component('PublicContact');

=head1 DESCRIPTION

This module exists to be called from L<Cpanel::Pkgacct>. It should not be
invoked directly except from that module.

It backs up the user’s Public Contact information.

=head1 METHODS

=cut

use strict;
use warnings;

use parent 'Cpanel::Pkgacct::Component';

use Cpanel::FileUtils::Write ();
use Cpanel::PublicContact    ();

use constant RELATIVE_PATH => 'public_contact.json';

=head2 I<OBJ>->perform()

This is just here to satisfy cplint. Don’t call this directly.

=cut

sub perform {
    my ($self) = @_;

    my $json_sr = Cpanel::PublicContact->get_json_sr( $self->get_user() );

    if ($$json_sr) {

        #save the new way
        Cpanel::FileUtils::Write::overwrite(
            $self->get_work_dir() . '/' . RELATIVE_PATH(),
            $$json_sr,
        );
    }

    return 1;
}

1;
