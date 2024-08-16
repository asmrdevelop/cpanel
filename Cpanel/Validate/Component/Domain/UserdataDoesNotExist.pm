package Cpanel::Validate::Component::Domain::UserdataDoesNotExist;

# cpanel - Cpanel/Validate/Component/Domain/UserdataDoesNotExist.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use base qw ( Cpanel::Validate::Component );

use Cpanel::Config::userdata::Load  ();
use Cpanel::Config::userdata::Utils ();
use Cpanel::Exception               ();

sub init {
    my ( $self, %OPTS ) = @_;

    $self->add_required_arguments(qw( domain ownership_user ));
    $self->add_optional_arguments(qw( main_userdata_ref user_domains_ar ));
    my @validation_arguments = $self->get_validation_arguments();
    @{$self}{@validation_arguments} = @OPTS{@validation_arguments};

    return;
}

sub validate {
    my ($self) = @_;

    $self->validate_arguments();

    my ( $domain, $user, $userdata_ref, $user_domains_ar ) = @{$self}{ $self->get_validation_arguments() };

    if ( !$user_domains_ar ) {
        if ($userdata_ref) {
            Cpanel::Config::userdata::Utils::sanitize_main_userdata($userdata_ref);
            $user_domains_ar = Cpanel::Config::userdata::Utils::get_all_domains_from_main_userdata_ar($userdata_ref);
        }
        else {
            $user_domains_ar = Cpanel::Config::userdata::Load::get_all_domains_for_user_ar($user);
        }
    }

    # Check the main domain first
    return if $domain eq $user_domains_ar->[0];

    # Avoid grep as we are usually just looking for the last one
    for ( reverse @$user_domains_ar ) {
        return if $domain eq $_;    # it exists
    }

    die Cpanel::Exception::create( 'DomainDoesNotExist', 'The domain “[_1]” does not exist in the [asis,userdata] for the user “[_2]”.', [ $domain, $user ] );
}

1;
