#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - Cpanel/Admin/Modules/Cpanel/externalauthentication_call.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Admin::Modules::Cpanel::externalauthentication_call;

use strict;
use warnings;

use parent qw( Cpanel::Admin::Base );

use Cpanel::Exception                      ();
use Cpanel::Security::Authn::User::Modify  ();
use Cpanel::AccessControl                  ();
use Cpanel::Validate::OpenIdConnect        ();
use Cpanel::Security::Authn::OpenIdConnect ();

# XXX Please don’t add to this list.
use constant _actions__pass_exception => (
    'ADD_AUTHN_LINK',
    'REMOVE_AUTHN_LINK',
    'REMOVE_ALL_AUTHN_LINKS_FOR_USER'
);

# Add to this list instead.
use constant _actions => (
    _actions__pass_exception(),
);

sub _demo_actions {
    return ();
}

sub ADD_AUTHN_LINK {
    my ( $self, $ref ) = @_;
    my $caller_username = $self->get_caller_username();

    my $service_name = $ref->{'service'} || 'cpaneld';

    Cpanel::Validate::OpenIdConnect::check_service_name_or_die($service_name);
    if ( $service_name ne 'cpaneld' && $service_name ne 'webmaild' ) {    # don't allow WHM
        die Cpanel::Exception::create( 'InvalidParameter', 'The service “[_1]” is not valid.', [$service_name] );
    }

    local $Cpanel::App::appname = $service_name;

    # Make sure the provider is real
    Cpanel::Security::Authn::OpenIdConnect::get_openid_provider( $service_name, $ref->{'provider'} );

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'account' ] ) unless length $ref->{'account'};

    if ( Cpanel::AccessControl::user_has_access_to_account( $caller_username, $ref->{'account'} ) ) {
        return Cpanel::Security::Authn::User::Modify::add_authn_link_for_user( $ref->{'account'}, 'openid_connect', $ref->{'provider'}, $ref->{'subject_unique_identifier'}, { 'preferred_username' => $ref->{'preferred_username'} } );
    }
    else {
        die Cpanel::Exception->create( "The user “[_1]” does not have access to the account “[_2]”.", [ $caller_username, $ref->{'account'} ] );
    }
}

sub REMOVE_AUTHN_LINK {
    my ( $self, $ref ) = @_;

    my $caller_username = $self->get_caller_username();
    die Cpanel::Exception::create( 'MissingParameter', [ name => 'account' ] ) unless length $ref->{'account'};
    if ( Cpanel::AccessControl::user_has_access_to_account( $caller_username, $ref->{'account'} ) ) {
        return Cpanel::Security::Authn::User::Modify::remove_authn_link_for_user( $ref->{'account'}, 'openid_connect', $ref->{'provider'}, $ref->{'subject_unique_identifier'} );
    }
    else {
        die Cpanel::Exception->create( "The user “[_1]” does not have access to the account “[_2]”.", [ $caller_username, $ref->{'account'} ] );
    }
}

sub REMOVE_ALL_AUTHN_LINKS_FOR_USER {
    my ( $self, $ref ) = @_;

    my $caller_username = $self->get_caller_username();
    die Cpanel::Exception::create( 'MissingParameter', [ name => 'account' ] ) unless length $ref->{'account'};
    if ( Cpanel::AccessControl::user_has_access_to_account( $caller_username, $ref->{'account'} ) ) {
        Cpanel::Validate::OpenIdConnect::check_user_exists_or_die( $ref->{'account'} );
        return Cpanel::Security::Authn::User::Modify::remove_all_authn_links_for_users( [ $ref->{'account'} ] );
    }
    else {
        die Cpanel::Exception->create( "The user “[_1]” does not have access to the account “[_2]”.", [ $caller_username, $ref->{'account'} ] );
    }
}

#----------------------------------------------------------------------

1;
