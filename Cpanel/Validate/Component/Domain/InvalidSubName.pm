package Cpanel::Validate::Component::Domain::InvalidSubName;

# cpanel - Cpanel/Validate/Component/Domain/InvalidSubName.pm
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

    $self->add_required_arguments(qw( domain ));
    my @validation_arguments = $self->get_validation_arguments();
    @{$self}{@validation_arguments} = @OPTS{@validation_arguments};

    return;
}

sub validate {
    my ($self) = @_;

    $self->validate_arguments();

    my ($domain) = @{$self}{ $self->get_validation_arguments() };

    if ( !Cpanel::Validate::SubDomain::is_valid($domain) ) {
        die Cpanel::Exception::create( 'SubdomainNameNotRfcCompliant', [$domain] );
    }

    return;
}

1;
