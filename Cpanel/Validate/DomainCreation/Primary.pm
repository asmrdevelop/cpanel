package Cpanel::Validate::DomainCreation::Primary;

# cpanel - Cpanel/Validate/DomainCreation/Primary.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base qw (
  Cpanel::Validate::DomainCreation
);

use Cpanel::Validate::Component::Domain::InvalidName                      ();
use Cpanel::Validate::Component::Domain::IsAccountName                    ();
use Cpanel::Validate::Component::Domain::IsHostname                       ();
use Cpanel::Validate::Component::Domain::IsPublicSuffix                   ();
use Cpanel::Validate::Component::Domain::IsCommon                         ();
use Cpanel::Validate::Component::Domain::HasDnsEntry                      ();
use Cpanel::Validate::Component::Domain::OwnedByAnotherUser               ();
use Cpanel::Validate::Component::Domain::AutoSubdomainsOwnedByAnotherUser ();
use Cpanel::Validate::Component::Domain::HasDynamicDns                    ();
use Cpanel::Validate::Component::Domain::HasUserDataDomainsEntry          ();

sub init {
    my ( $self, $user_provided_argument_hash, $system_provided_arguments_hash ) = @_;

    $self->SUPER::init( $self, $user_provided_argument_hash, $system_provided_arguments_hash );

    $self->add_user_provided_arguments(qw( domain ));
    $self->add_required_arguments(qw( validation_context ));
    $self->add_optional_arguments(qw( forcedns ));

    delete $system_provided_arguments_hash->{'domain'};
    @{$self}{qw( domain )} = @{$user_provided_argument_hash}{qw( domain )};

    my @system_provided_arguments = $self->get_system_provided_arguments();

    # We need to do this twice to account for variables needed in initialization
    @{$self}{@system_provided_arguments} = @{$system_provided_arguments_hash}{@system_provided_arguments};
    $self->validate_arguments();

    $self->validate_context( $system_provided_arguments_hash->{'validation_context'} );

    # Create a combined hash for readability, passing in the user provided arguments first so if an argument happens to slip by that
    # we already provide it will be overwritten by the system provided arguments.
    my %combined_input = ( %{$user_provided_argument_hash}, %{$system_provided_arguments_hash} );

    my $forcedns = ( ( $system_provided_arguments_hash->{'forcedns'} || 0 ) == 1 ) ? 1 : 0;

    $self->add_validation_components(
        Cpanel::Validate::Component::Domain::InvalidName->new(%combined_input),
        Cpanel::Validate::Component::Domain::IsAccountName->new(%combined_input),
        Cpanel::Validate::Component::Domain::IsHostname->new(%combined_input),
        Cpanel::Validate::Component::Domain::IsPublicSuffix->new(%combined_input),
        Cpanel::Validate::Component::Domain::IsCommon->new(%combined_input),
        Cpanel::Validate::Component::Domain::HasUserDataDomainsEntry->new(%combined_input),
        Cpanel::Validate::Component::Domain::HasDynamicDns->new(%combined_input),
        $forcedns                          ? () : Cpanel::Validate::Component::Domain::HasDnsEntry->new(%combined_input),
        $self->has_root()                  ? () : Cpanel::Validate::Component::Domain::OwnedByAnotherUser->new(%combined_input),
        ( $forcedns && $self->has_root() ) ? () : Cpanel::Validate::Component::Domain::AutoSubdomainsOwnedByAnotherUser->new( domain => $self->{'domain'} ),
    );

    # Set all the arguments again, including the ones just added by components
    my @get_system_provided_arguments = $self->get_system_provided_arguments();
    @{$self}{@get_system_provided_arguments} = @{$system_provided_arguments_hash}{@get_system_provided_arguments};

    return $self;
}

1;
