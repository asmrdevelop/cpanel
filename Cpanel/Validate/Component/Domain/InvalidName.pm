package Cpanel::Validate::Component::Domain::InvalidName;

# cpanel - Cpanel/Validate/Component/Domain/InvalidName.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base qw ( Cpanel::Validate::Component );

use Cpanel::Exception        ();
use Cpanel::Validate::Domain ();

sub init {
    my ( $self, %OPTS ) = @_;

    $self->add_required_arguments(qw( domain ));
    my @validation_arguments = $self->get_validation_arguments();
    @{$self}{@validation_arguments} = @OPTS{@validation_arguments};

    return;
}

sub validate {
    my ($self) = @_;

    $self->validate_arguments();

    my ( $domain, $username ) = @{$self}{ $self->get_validation_arguments() };

    if ( !Cpanel::Validate::Domain::is_valid_cpanel_domain( $domain, my $why ) ) {
        die Cpanel::Exception::create( 'DomainNameNotAllowed', [ given => $domain, why => $why ] );
    }

    return;
}

1;
