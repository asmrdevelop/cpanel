package Cpanel::Validate::Component::Domain::IsReservedSubdomain;

# cpanel - Cpanel/Validate/Component/Domain/IsReservedSubdomain.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base qw ( Cpanel::Validate::Component );

use Cpanel::Exception           ();
use Cpanel::Validate::SubDomain ();

sub init {
    my ( $self, %OPTS ) = @_;

    $self->add_required_arguments(qw( sub_domain ));
    my @validation_arguments = $self->get_validation_arguments();
    @{$self}{@validation_arguments} = @OPTS{@validation_arguments};

    return;
}

sub validate {
    my ($self) = @_;

    $self->validate_arguments();

    my ($subdomain) = @{$self}{ $self->get_validation_arguments() };

    if ( Cpanel::Validate::SubDomain::is_reserved($subdomain) ) {
        die Cpanel::Exception::create( 'ReservedSubdomain', 'The subdomain “[_1]” is reserved.', [$subdomain] );
    }

    return;
}

1;
