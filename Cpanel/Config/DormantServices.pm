package Cpanel::Config::DormantServices;

# cpanel - Cpanel/Config/DormantServices.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Config::DormantServices

=head1 DESCRIPTION

Logic for dormant-capable services.

=cut

#----------------------------------------------------------------------

use Cpanel::Analytics                      ();
use Cpanel::DAV::Ports                     ();
use Cpanel::Server::Type::Role::SpamFilter ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 @services = get_hidden()

Returns a list of dormant-capable services that should be hidden from
controls.

=cut

sub get_hidden {
    my @exclude;

    if ( !Cpanel::Server::Type::Role::SpamFilter->is_enabled() ) {
        push @exclude, 'spamd';
    }

    if ( !%{ Cpanel::DAV::Ports::get_ports() } ) {
        push @exclude, 'cpdavd';
    }

    return @exclude;
}

1;
