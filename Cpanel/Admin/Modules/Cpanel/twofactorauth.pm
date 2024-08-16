#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - Cpanel/Admin/Modules/Cpanel/twofactorauth.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Admin::Modules::Cpanel::twofactorauth;

use strict;
use warnings;

use parent qw( Cpanel::Admin::Base );

use Cpanel::BinCheck                                 ();
use Cpanel::Config::userdata::TwoFactorAuth::Secrets ();
use Cpanel::Config::userdata::TwoFactorAuth::Issuers ();
use Whostmgr::API::1::TwoFactorAuth                  ();
use Cpanel::Exception();

sub _actions {
    return qw(GET_USER_CONFIGURATION GET_USER_ISSUER SET_USER_CONFIGURATION REMOVE_USER_CONFIGURATION GENERATE_USER_CONFIGURATION VERIFY_TOKEN GET_TEAM_USER_CONFIGURATION);
}

# tested directly
sub _allowed_parents {
    return (
        __PACKAGE__->SUPER::_allowed_parents(),
        '/usr/local/cpanel/base/securitypolicy.cgi',
    );
}

sub GET_USER_CONFIGURATION {
    my ( $self, $tfa_username, $app_name ) = @_;
    $self->_validate_tfa_username( $tfa_username, $app_name );

    # This call is exempt from the 'feature check' as users can be
    # left in a weird state, where they have configured 2FA on their account,
    # but had the feature removed AFTER setup.
    #
    # Enforcing the feature check here would cause the login attempts to fail
    # with a Security Policy exec error, and require the reseller/admin to
    # remove the 2FA configuration via WHM.

    my $tfa_manager = Cpanel::Config::userdata::TwoFactorAuth::Secrets->new( { 'read_only' => 1 } );
    if ( $tfa_manager->read_userdata()->{$tfa_username} ) {
        my $issuer = Cpanel::Config::userdata::TwoFactorAuth::Issuers->new( { 'read_only' => 1 } )->get_issuer($tfa_username);
        return { 'is_enabled' => 1, 'issuer' => $issuer };
    }
    return { 'is_enabled' => 0 };
}

sub GET_USER_ISSUER {
    my $self     = shift;
    my $username = $self->get_caller_username();

    return Cpanel::Config::userdata::TwoFactorAuth::Issuers->new( { 'read_only' => 1 } )->get_issuer($username);
}

sub SET_USER_CONFIGURATION {
    my ( $self, $args ) = @_;
    $self->cpuser_has_feature_or_die('twofactorauth');
    $self->_validate_tfa_username( $args->{tfa_username}, $args->{app_name} );

    $args->{'user'}   = $args->{tfa_username};
    $args->{'origin'} = 'cpanel';
    my $metadata = {};
    Whostmgr::API::1::TwoFactorAuth::twofactorauth_set_tfa_config( $args, $metadata );

    return $metadata;
}

sub REMOVE_USER_CONFIGURATION {
    my ( $self, $tfa_username, $app_name ) = @_;
    $self->cpuser_has_feature_or_die('twofactorauth');
    $self->_validate_tfa_username( $tfa_username, $app_name );

    local $ENV{REMOTE_USER} = $tfa_username;
    my $metadata = {};
    my $output   = Whostmgr::API::1::TwoFactorAuth::twofactorauth_remove_user_config( { 'user' => $tfa_username, 'origin' => 'cpanel' }, $metadata );
    return $output;
}

sub GENERATE_USER_CONFIGURATION {
    my ( $self, $tfa_username, $app_name ) = @_;

    $self->_validate_tfa_username( $tfa_username, $app_name );
    my $metadata = {};
    my $output   = Whostmgr::API::1::TwoFactorAuth::twofactorauth_generate_tfa_config( { 'user' => $tfa_username }, $metadata );
    if ( $metadata->{'result'} ) {
        return $output;
    }

    return $metadata->{'reason'};
}

sub VERIFY_TOKEN {
    my ( $self, $token, $sec_ctxt ) = @_;
    my $tfa_username;
    if ( $sec_ctxt->{appname} eq 'webmaild' ) {
        $tfa_username = $sec_ctxt->{user};
    }
    elsif ( $ENV{TEAM_USER} ) {
        $tfa_username = "$ENV{'TEAM_USER'}\@$ENV{'TEAM_OWNER'}";
    }
    else {
        $tfa_username = $self->get_caller_username();
    }

    $self->_validate_tfa_username( $tfa_username, $sec_ctxt->{appname} );
    require Cpanel::Security::Authn::TwoFactorAuth::Verify;

    return Cpanel::Security::Authn::TwoFactorAuth::Verify::verify_token_for_user( $tfa_username, $token, $sec_ctxt->{session_id} );
}

sub GET_TEAM_USER_CONFIGURATION {
    my ( $self, $team_user ) = @_;

    # This call is exempt from the 'feature check' as users can be
    # left in a weird state, where they have configured 2FA on their account,
    # but had the feature removed AFTER setup.
    #
    # Enforcing the feature check here would cause the login attempts to fail
    # with a Security Policy exec error, and require the reseller/admin to
    # remove the 2FA configuration via WHM.

    my $team_owner = $self->get_caller_username();
    require Cpanel::Team::Config;
    my $team_obj = Cpanel::Team::Config->new($team_owner);
    my $team     = $team_obj->get_team_user($team_user);     # Validate if team_user is valid.

    my $team_user_2fa_name = "$team_user\@$team_owner";
    my $tfa_manager        = Cpanel::Config::userdata::TwoFactorAuth::Secrets->new( { 'read_only' => 1 } );
    if ( $tfa_manager->read_userdata()->{$team_user_2fa_name} ) {
        my $issuer = Cpanel::Config::userdata::TwoFactorAuth::Issuers->new( { 'read_only' => 1 } )->get_issuer($team_user_2fa_name);
        return { 'is_enabled' => 1, 'issuer' => $issuer };
    }
    return { 'is_enabled' => 0 };
}

# Validate arguments passed to AdminBin.
# This avoids caller of AdminBin to influence
# the behavior of API calls by passing invalid tfa usernames.
sub _validate_tfa_username {
    my ( $self, $tfa_username, $app_name ) = @_;
    if ( $tfa_username =~ /@/ && $app_name =~ /^(webmail|webmaild)$/ ) {
        my $domain = ( split /@/, $tfa_username )[1];
        $self->verify_that_cpuser_owns_domain($domain);
    }
    elsif ( $tfa_username =~ /@/ && $app_name eq 'cpaneld' ) {
        my ( $team_user, $team_owner ) = split /@/, $tfa_username;
        die Cpanel::Exception::create( 'InvalidParameter', "You do not own the team user account “[_1]”.", [$team_user] ) if $team_owner ne $self->get_caller_username();
        $self->get_caller_team_user();    # dies if team user is invalid
    }
    else {
        die Cpanel::Exception::create( 'InvalidParameter', "You do not own the “[_1]” cPanel account.", [$tfa_username] ) if $tfa_username ne $self->get_caller_username();
    }
    return;
}

1;
