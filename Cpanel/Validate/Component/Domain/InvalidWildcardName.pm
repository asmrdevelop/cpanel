package Cpanel::Validate::Component::Domain::InvalidWildcardName;

# cpanel - Cpanel/Validate/Component/Domain/InvalidWildcardName.pm
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

    my ($domain) = @{$self}{ $self->get_validation_arguments() };

    my $quiet = 1;
    die Cpanel::Exception::create( 'InvalidWildcardDomainName', [$domain] )            if !Cpanel::Validate::Domain::is_valid_wildcard_domain($domain);
    die Cpanel::Exception::create( 'DomainNameNotRfcCompliant', [ given => $domain ] ) if !Cpanel::Validate::Domain::valid_wild_domainname( $domain, $quiet );

    return;
}

1;
