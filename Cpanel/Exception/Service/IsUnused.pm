package Cpanel::Exception::Service::IsUnused;

# cpanel - Cpanel/Exception/Service/IsUnused.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Exception::Service::IsUnused

=head1 DESCRIPTION

An exception to indicate that no roles on the server use the given service.

=cut

#----------------------------------------------------------------------

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

#----------------------------------------------------------------------

#Parameters:
#
#   service - optional, the name of the service
#
sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new(
        'No enabled roles on this system use the “[_1]” service.',
        $self->{'_metadata'}{'service'},
    );
}

1;
