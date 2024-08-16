package Cpanel::Validate::Component::Domain::IsAccountName;

# cpanel - Cpanel/Validate/Component/Domain/IsAccountName.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base qw ( Cpanel::Validate::Component );

use Cpanel::Exception ();
use Cpanel::PwCache   ();

sub init {
    my ( $self, %OPTS ) = @_;

    $self->add_required_arguments(qw( domain ownership_user ));
    my @validation_arguments = $self->get_validation_arguments();
    @{$self}{@validation_arguments} = @OPTS{@validation_arguments};

    return;
}

sub validate {
    my ($self) = @_;

    $self->validate_arguments();

    my ( $domain, $username ) = @{$self}{ $self->get_validation_arguments() };

    # This was a problem for some Plesk systems transferring to us.
    die Cpanel::Exception::create( 'DomainNameNotAllowed', 'The domain name may not be the same as a username.' ) if $domain eq $username;

    # Check to see if this domain matches any user already on the system. We don't want to say there is user on the server with that name though.
    die Cpanel::Exception::create( 'DomainNameNotAllowed', 'The supplied domain name is invalid.' ) if Cpanel::PwCache::getpwnam_noshadow($domain);

    return;
}

1;
