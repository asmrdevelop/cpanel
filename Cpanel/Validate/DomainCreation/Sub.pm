package Cpanel::Validate::DomainCreation::Sub;

# cpanel - Cpanel/Validate/DomainCreation/Sub.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use base qw (
  Cpanel::Validate::DomainCreation
);

use Cpanel::Config::userdata::Load                                    ();
use Cpanel::Validate::Domain::Normalize                               ();
use Cpanel::Validate::Component::Account::OverLimit                   ();
use Cpanel::Validate::Component::Domain::IsHostname                   ();
use Cpanel::Validate::Component::Domain::IsProxySubdomainWithDnsEntry ();
use Cpanel::Validate::Component::Domain::IsReservedSubdomain          ();
use Cpanel::Validate::Component::Domain::InvalidSubName               ();
use Cpanel::Validate::Component::Domain::InvalidWildcardName          ();
use Cpanel::Validate::Component::Domain::UserdataExists               ();
use Cpanel::Validate::Component::Domain::UserdataDoesNotExist         ();
use Cpanel::Validate::Component::Domain::HasDynamicDns                ();
use Cpanel::Validate::Component::Domain::HasUserDataDomainsEntry      ();

sub init {
    my ( $self, $user_provided_argument_hash, $system_provided_arguments_hash ) = @_;

    $self->SUPER::init( $self, $user_provided_argument_hash, $system_provided_arguments_hash );

    $self->add_user_provided_arguments(qw( sub_domain target_domain root_domain ));
    $self->add_required_arguments(qw( ownership_user target_domain sub_domain root_domain ));
    $self->add_optional_arguments(qw( main_userdata_ref force validation_context user_domains_ar ));
    $self->add_internal_arguments('domain');

    delete @{$system_provided_arguments_hash}{qw( sub_domain target_domain root_domain )};
    @{$self}{qw( sub_domain target_domain root_domain )} = @{$user_provided_argument_hash}{qw( sub_domain target_domain root_domain )};

    my @system_provided_arguments = $self->get_system_provided_arguments();

    # We need to do this twice to account for variables needed in initialization
    @{$self}{@system_provided_arguments} = @{$system_provided_arguments_hash}{@system_provided_arguments};
    $self->validate_arguments();

    if ( $system_provided_arguments_hash->{'validation_context'} ) {
        $self->validate_context( $system_provided_arguments_hash->{'validation_context'} );
    }

    my $quiet = 1;
    $user_provided_argument_hash->{'sub_domain'}    = Cpanel::Validate::Domain::Normalize::normalize( $user_provided_argument_hash->{'sub_domain'}, $quiet );    # We know the subdomain isn't a completely valid domain, don't warn about it
    $user_provided_argument_hash->{'target_domain'} = Cpanel::Validate::Domain::Normalize::normalize( $user_provided_argument_hash->{'target_domain'} );

    $system_provided_arguments_hash->{'domain'} = $user_provided_argument_hash->{'sub_domain'} . '.' . $user_provided_argument_hash->{'target_domain'};

    my $force = $system_provided_arguments_hash->{'force'} ? 1 : 0;

    my $is_whm_context = $self->is_whm_context();
    my $userdata_main_ref;
    if ( !$is_whm_context ) {
        if ( $system_provided_arguments_hash->{'main_userdata_ref'} && ref $system_provided_arguments_hash->{'main_userdata_ref'} ) {
            $userdata_main_ref = $system_provided_arguments_hash->{'main_userdata_ref'};
        }
        else {
            $userdata_main_ref = Cpanel::Config::userdata::Load::load_userdata_main( $system_provided_arguments_hash->{'ownership_user'} );
        }
    }

    # Don't display these in $self->get_validation_arguments* as they don't need to be passed in
    $self->add_internal_arguments(qw( limit_name limit_display_name limit_current_count current_limit ));

    # Create a combined hash for readability, passing in the user provided arguments first so if an argument happens to slip by that
    # we already provide it will be overwritten by the system provided arguments.
    my %combined_input = ( %{$user_provided_argument_hash}, %{$system_provided_arguments_hash} );

    $self->add_validation_components(
        Cpanel::Validate::Component::Domain::InvalidSubName->new(%combined_input),
        Cpanel::Validate::Component::Domain::InvalidWildcardName->new(%combined_input),
        Cpanel::Validate::Component::Domain::IsReservedSubdomain->new(%combined_input),
        Cpanel::Validate::Component::Domain::IsHostname->new(%combined_input),
        $is_whm_context ? () : Cpanel::Validate::Component::Account::OverLimit->new(
            %combined_input,
            'limit_name'          => 'MAXSUB',
            'limit_display_name'  => 'subdomains',
            'limit_current_count' => scalar @{ $userdata_main_ref->{'sub_domains'} }
        ),
        Cpanel::Validate::Component::Domain::UserdataDoesNotExist->new( %combined_input, 'domain' => $user_provided_argument_hash->{'root_domain'} ),
        Cpanel::Validate::Component::Domain::IsProxySubdomainWithDnsEntry->new(%combined_input),
        Cpanel::Validate::Component::Domain::UserdataExists->new(%combined_input),
        Cpanel::Validate::Component::Domain::HasUserDataDomainsEntry->new(%combined_input),
        Cpanel::Validate::Component::Domain::HasDynamicDns->new(%combined_input),
    );

    # Set all the arguments again, including the ones just added by components
    my @get_system_provided_arguments = $self->get_system_provided_arguments();
    @{$self}{@get_system_provided_arguments} = @{$system_provided_arguments_hash}{@get_system_provided_arguments};

    return $self;
}

1;
