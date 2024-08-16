package Cpanel::Validate::Component::Domain::OwnedByAnotherUser;

# cpanel - Cpanel/Validate/Component/Domain/OwnedByAnotherUser.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use base qw ( Cpanel::Validate::Component );

use Cpanel::AcctUtils::DomainOwner ();
use Cpanel::Config::LoadCpConf     ();
use Cpanel::Exception              ();
use Cpanel::App                    ();

sub init {
    my ( $self, %OPTS ) = @_;

    $self->add_required_arguments(qw( domain ownership_user ));

    if ( Cpanel::App::is_whm() ) {
        $self->add_optional_arguments(qw( allowwhmparkonothers ));
        my @validation_arguments = $self->get_validation_arguments();
        @{$self}{@validation_arguments} = @OPTS{@validation_arguments};
        if ( !defined $self->{'allowwhmparkonothers'} ) {
            my $cpanel_config_ref = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
            $self->{'allowwhmparkonothers'} = $cpanel_config_ref->{'allowwhmparkonothers'} ? 1 : 0;
        }
    }
    else {
        $self->add_optional_arguments(qw( allowparkonothers ));
        my @validation_arguments = $self->get_validation_arguments();
        @{$self}{@validation_arguments} = @OPTS{@validation_arguments};
        if ( !defined $self->{'allowparkonothers'} ) {
            my $cpanel_config_ref = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
            $self->{'allowparkonothers'} = $cpanel_config_ref->{'allowparkonothers'} ? 1 : 0;
        }
    }

    return;
}

sub validate {
    my ($self) = @_;

    $self->validate_arguments();

    my ( $domain, $user, $allow_parked ) = @{$self}{ $self->get_validation_arguments() };

    if ( !$allow_parked ) {
        my ( $user_can_own, $owned_domain, $owning_user ) = Cpanel::AcctUtils::DomainOwner::check_each_domain_level_for_ownership( $user, $domain );
        if ( !$user_can_own ) {
            if ( Cpanel::App::is_whm() && _hasroot() ) {
                if ( length $owning_user ) {
                    die Cpanel::Exception::create( 'DomainOwnership', 'The domain “[_1]” may not be created by “[_2]” because “[_3]” is already owned by “[_4]”.', [ $domain, $user, $owned_domain, $owning_user ] );
                }
                else {
                    die Cpanel::Exception::create( 'DomainOwnership', 'The domain “[_1]” may not be created by “[_2]” because a [asis,DNS] zone already exists for the domain, “[_3]”.', [ $domain, $user, $owned_domain ] );

                }
            }
            else {
                die Cpanel::Exception::create( 'DomainOwnership', 'The domain “[_1]” may not be created by “[_2]” because “[_3]” is already owned by another user.', [ $domain, $user, $owned_domain ] );
            }
        }
    }

    return;
}

sub _hasroot {
    require Whostmgr::ACLS;
    Whostmgr::ACLS::init_acls();
    return Whostmgr::ACLS::hasroot();
}

1;
