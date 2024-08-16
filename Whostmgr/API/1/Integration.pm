package Whostmgr::API::1::Integration;

# cpanel - Whostmgr/API/1/Integration.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Integration         ();
use Cpanel::Integration::Config ();
use Whostmgr::Authz             ();
use Whostmgr::Integration       ();
use Whostmgr::API::1::Utils     ();

use constant NEEDS_ROLE => {
    create_integration_group         => undef,
    create_integration_link          => undef,
    get_integration_link_user_config => undef,
    list_integration_groups          => undef,
    list_integration_links           => undef,
    remove_integration_group         => undef,
    remove_integration_link          => undef,
    update_integration_link_token    => undef,
};

###########################################################################
#
# Method:
#   create_integration_link
#
# Description:
#   Create an integration link with an external application for a user
#   that will appear in their cPanel UI
#
# Parameters:
#   see Whostmgr::Integration::add_link
#
sub create_integration_link {
    my ( $args, $metadata ) = @_;

    # autologin_token_url is preferred but not required
    _validate_request( $args, qw(app) );

    my %args_copy = %$args;

    Whostmgr::Integration::add_link(
        delete( $args_copy{'user'} ),
        delete( $args_copy{'app'} ),
        \%args_copy,
    );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return;
}

###########################################################################
#
# Method:
#   create_integration_group
#
# Description:
#   Create an integration group for a user
#   that will appear in their cPanel UI
#
# Parameters:
#   see Whostmgr::Integration::add_group
#
sub create_integration_group {
    my ( $args, $metadata ) = @_;

    # autologin_token_url is preferred but not required
    _validate_request( $args, qw(group_id) );

    my %args_copy = %$args;

    Whostmgr::Integration::add_group(
        delete( $args_copy{'user'} ),
        delete( $args_copy{'group_id'} ),
        \%args_copy,
    );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return;
}

###########################################################################
#
# Method:
#   update_integration_link_token
#
# Description:
#   Update the token in an an integration link for an app.
#
# Parameters:
#   see Whostmgr::Integration::update_token
#

sub update_integration_link_token {
    my ( $args, $metadata ) = @_;

    _validate_request( $args, qw(token app) );

    Whostmgr::Integration::update_token( $args->{'user'}, $args->{'app'}, $args->{'token'} );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return;
}

###########################################################################
#
# Method:
#   remove_integration_link
#
# Description:
#   Remove an integration link for an app.
#
# Parameters:
#   see Whostmgr::Integration::remove_link
#

sub remove_integration_link {
    my ( $args, $metadata ) = @_;

    _validate_request( $args, qw(app) );

    Whostmgr::Integration::remove_link( $args->{'user'}, $args->{'app'} );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return;
}

###########################################################################
#
# Method:
#   remove_integration_group
#
# Description:
#   Remove an integration group for an user.
#
# Parameters:
#   see Whostmgr::Integration::remove_group
#

sub remove_integration_group {
    my ( $args, $metadata ) = @_;

    _validate_request( $args, qw(group_id) );

    Whostmgr::Integration::remove_group( $args->{'user'}, $args->{'group_id'} );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return;
}

###########################################################################
#
# Method:
#   list_integration_links
#
# Description:
#   Provide a list of integration links for a user
#
# Parameters:
#   see Whostmgr::Integration::list_links
#

sub list_integration_links {
    my ( $args, $metadata ) = @_;

    _validate_request($args);

    my @apps = Whostmgr::Integration::list_links( $args->{'user'} );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return { 'links' => [ map { { 'app' => $_ } } @apps ] };
}

###########################################################################
#
# Method:
#   list_integration_groups
#
# Description:
#   Provide a list of integration groups for a user
#
# Parameters:
#   see Whostmgr::Integration::list_groups

sub list_integration_groups {
    my ( $args, $metadata ) = @_;

    _validate_request($args);

    my @groups = Cpanel::Integration::Config::get_groups_for_user( $args->{'user'} );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return { 'links' => [ map { { 'group' => $_ } } @groups ] };
}

###########################################################################
#
# Method:
#   get_integration_link_user_config
#
# Description:
#   Provide the configuration for an existing integration link
#
# Parameters:
#   “user” and “app”, as used by Cpanel::Integration::load_user_app_config()
#

sub get_integration_link_user_config {
    my ( $args, $metadata ) = @_;

    _validate_request( $args, qw(app) );

    my $link_config = Cpanel::Integration::load_user_app_config( $args->{'user'}, $args->{'app'} );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return { 'userconfig' => $link_config };
}

sub _validate_request {
    my ( $args_hr, @reqd_args ) = @_;

    foreach my $required ( 'user', @reqd_args ) {
        Whostmgr::API::1::Utils::get_length_required_argument( $args_hr, $required );
    }

    Whostmgr::Authz::verify_account_access( $args_hr->{'user'} );

    return;
}

1;
