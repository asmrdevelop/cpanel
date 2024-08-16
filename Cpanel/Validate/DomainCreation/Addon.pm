package Cpanel::Validate::DomainCreation::Addon;

# cpanel - Cpanel/Validate/DomainCreation/Addon.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base qw (
  Cpanel::Validate::DomainCreation
);

use Cpanel::Config::userdata::Load                                 ();
use Cpanel::Exception                                              ();
use Cpanel::Validate::Domain::Normalize                            ();
use Cpanel::Validate::Component::Domain::ContainsReservedSubdomain ();
use Cpanel::Validate::Component::Domain::InvalidName               ();
use Cpanel::Validate::Component::Domain::IsAccountName             ();
use Cpanel::Validate::Component::Domain::IsHostname                ();
use Cpanel::Validate::Component::Domain::IsPublicSuffix            ();
use Cpanel::Validate::Component::Domain::IsCommon                  ();
use Cpanel::Validate::Component::Domain::HasDnsEntry               ();
use Cpanel::Validate::Component::Account::MissingFeature           ();
use Cpanel::Validate::Component::Account::OverLimit                ();
use Cpanel::Validate::Component::Domain::UserdataExists            ();
use Cpanel::Validate::Component::Domain::OwnedByAnotherUser        ();
use Cpanel::Validate::Component::Domain::UserdataDoesNotExist      ();
use Cpanel::Validate::Component::Domain::DomainRegistration        ();
use Cpanel::Validate::Component::Domain::HasUserDataDomainsEntry   ();

sub init {
    my ( $self, $user_provided_argument_hash, $system_provided_arguments_hash ) = @_;

    $self->SUPER::init( $self, $user_provided_argument_hash, $system_provided_arguments_hash );

    $self->add_user_provided_arguments(qw( domain target_domain ));

    $self->add_required_arguments(qw( domain ownership_user target_domain ));
    $self->add_optional_arguments(qw( force main_userdata_ref validation_context ));

    delete @{$system_provided_arguments_hash}{qw( domain target_domain )};
    @{$self}{qw( domain target_domain )} = @{$user_provided_argument_hash}{qw( domain target_domain )};

    my @system_provided_arguments = $self->get_system_provided_arguments();

    # We need to do this twice to account for variables needed in initialization
    @{$self}{@system_provided_arguments} = @{$system_provided_arguments_hash}{@system_provided_arguments};
    $self->validate_arguments();

    $user_provided_argument_hash->{'domain'}        = Cpanel::Validate::Domain::Normalize::normalize( $user_provided_argument_hash->{'domain'} );
    $user_provided_argument_hash->{'target_domain'} = Cpanel::Validate::Domain::Normalize::normalize( $user_provided_argument_hash->{'target_domain'} );

    my $force = $system_provided_arguments_hash->{'force'} ? 1 : 0;

    my $userdata_main_ref;

    if ( $system_provided_arguments_hash->{'main_userdata_ref'} && ref $system_provided_arguments_hash->{'main_userdata_ref'} ) {
        $userdata_main_ref = $system_provided_arguments_hash->{'main_userdata_ref'};
    }
    else {
        $userdata_main_ref = Cpanel::Config::userdata::Load::load_userdata_main( $system_provided_arguments_hash->{'ownership_user'} );
    }

    my $user_main_domain = $userdata_main_ref->{'main_domain'};

    if ( !$user_main_domain ) {
        die Cpanel::Exception::create(
            'UserdataLookupFailure',
            'The system cannot determine the main domain of the user “[_1]”.',
            [ $system_provided_arguments_hash->{'ownership_user'} ],
        );
    }
    if ( $user_provided_argument_hash->{'target_domain'} eq $user_main_domain ) {
        die Cpanel::Exception::create(
            'InvalidParkedTarget',
            'You cannot create an addon domain that targets your main domain.'
        );
    }

    if (   $user_main_domain eq $user_provided_argument_hash->{'domain'}
        || $user_provided_argument_hash->{'target_domain'} eq $user_provided_argument_hash->{'domain'} ) {
        die Cpanel::Exception::create( 'InvalidParkedTarget', 'You cannot park a domain on top of itself!' );
    }

    # Don't display these in $self->get_validation_arguments* as they don't need to be passed in
    $self->add_internal_arguments(qw( limit_name limit_display_name limit_current_count current_limit feature_name ));

    # Create a combined hash for readability, passing in the user provided arguments first so if an argument happens to slip by that
    # we already provide it will be overwritten by the system provided arguments.
    my %combined_input = ( %{$user_provided_argument_hash}, %{$system_provided_arguments_hash} );

    $self->add_validation_components(

        # We could add a validation component here for account ownership, to see if the $ENV{'REMOTE_USER'} has access to the $ownership_user,
        # but currently this is handled by another portion of the code path. If this validator is used outside of Cpanel::ParkAdmin, we should probably add it.
        $force ? () : Cpanel::Validate::Component::Domain::InvalidName->new(%combined_input),
        Cpanel::Validate::Component::Domain::InvalidName->new( %combined_input, 'domain' => $user_provided_argument_hash->{'target_domain'} ),
        Cpanel::Validate::Component::Domain::ContainsReservedSubdomain->new(%combined_input),
        Cpanel::Validate::Component::Domain::HasUserDataDomainsEntry->new(%combined_input),
        $force ? () : Cpanel::Validate::Component::Domain::HasDnsEntry->new(%combined_input),
        Cpanel::Validate::Component::Domain::UserdataExists->new(%combined_input),
        Cpanel::Validate::Component::Domain::UserdataDoesNotExist->new( %combined_input, 'domain' => $user_provided_argument_hash->{'target_domain'} ),
        $self->has_root()       ? () : Cpanel::Validate::Component::Domain::OwnedByAnotherUser->new(%combined_input),
        $self->is_whm_context() ? () : Cpanel::Validate::Component::Account::MissingFeature->new( %combined_input, 'feature_name' => 'addondomains' ),
        $self->is_whm_context() ? () : Cpanel::Validate::Component::Account::OverLimit->new(
            %combined_input,
            'limit_name'          => 'MAXADDON',
            'limit_display_name'  => 'addon domains',
            'limit_current_count' => $userdata_main_ref->{'addon_domains'} ? scalar keys %{ $userdata_main_ref->{'addon_domains'} } : 0
        ),
        Cpanel::Validate::Component::Domain::IsAccountName->new(%combined_input),
        Cpanel::Validate::Component::Domain::IsHostname->new(%combined_input),
        Cpanel::Validate::Component::Domain::IsPublicSuffix->new(%combined_input),
        Cpanel::Validate::Component::Domain::IsCommon->new(%combined_input),
        $force ? () : Cpanel::Validate::Component::Domain::DomainRegistration->new(%combined_input),
    );

    # This second time is to initialize all of the extra required and optional arguments added by the validation components
    my @get_system_provided_arguments = $self->get_system_provided_arguments();
    @{$self}{@get_system_provided_arguments} = @{$system_provided_arguments_hash}{@get_system_provided_arguments};

    return $self;
}

1;
