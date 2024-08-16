package Cpanel::API::TwoFactorAuth;

# cpanel - Cpanel/API/TwoFactorAuth.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings) -- not fully vetted for warnings

our $VERSION = '1.0';
use Try::Tiny ();

use Cpanel::AdminBin::Call ();

my $allow_demo = { allow_demo => 1 };

our %API = (
    _needs_feature              => 'twofactorauth',
    get_user_configuration      => $allow_demo,
    set_user_configuration      => $allow_demo,
    generate_user_configuration => $allow_demo,
    remove_user_configuration   => $allow_demo,
    get_team_user_configuration => $allow_demo
);

sub get_user_configuration {
    my ( $args, $result ) = @_;
    my $tfa_username = _get_tfa_username();

    my $data = Cpanel::AdminBin::Call::call( 'Cpanel', 'twofactorauth', 'GET_USER_CONFIGURATION', $tfa_username, $Cpanel::appname );
    $result->data($data);

    return 1;
}

sub set_user_configuration {
    my ( $args, $result ) = @_;
    my $tfa_username = _get_tfa_username();

    my $tfa_args = {
        'secret'       => $args->get('secret'),
        'tfa_token'    => $args->get('tfa_token'),
        'tfa_username' => $tfa_username,
        'app_name'     => $Cpanel::appname
    };

    my $status = Cpanel::AdminBin::Call::call( 'Cpanel', 'twofactorauth', 'SET_USER_CONFIGURATION', $tfa_args );
    if ( $status->{'result'} ) {
        $result->data( { 'tfa_configured' => 1 } );
        return 1;
    }

    $result->error( 'Failed to set user configuration: [_1]', $status->{'reason'} );
    return;
}

sub generate_user_configuration {
    my ( $args, $result ) = @_;

    my $tfa_username = _get_tfa_username();
    my $config       = Cpanel::AdminBin::Call::call( 'Cpanel', 'twofactorauth', 'GENERATE_USER_CONFIGURATION', $tfa_username, $Cpanel::appname );
    if ( ref $config eq 'HASH' ) {
        $result->data($config);
        return 1;
    }

    $result->raw_error($config);
    return;
}

sub remove_user_configuration {
    my ( $args, $result ) = @_;

    my $tfa_username = _get_tfa_username();
    my $output       = Cpanel::AdminBin::Call::call( 'Cpanel', 'twofactorauth', 'REMOVE_USER_CONFIGURATION', $tfa_username, $Cpanel::appname );
    if ( 'ARRAY' eq ref $output->{'users_modified'} && $output->{'users_modified'}->[0] eq $tfa_username ) {
        $result->data( { 'tfa_removed' => 1 } );
        return 1;
    }

    $result->error( 'Failed to remove user configuration: [_1]', $output->{'failed'}->{$tfa_username} );
    return;
}

sub get_team_user_configuration {
    my ( $args, $result ) = @_;
    my $team_user = $args->get_length_required('team_user');

    my $data = Cpanel::AdminBin::Call::call( 'Cpanel', 'twofactorauth', 'GET_TEAM_USER_CONFIGURATION', $team_user );
    $result->data($data);

    return 1;
}

sub _get_tfa_username {
    if ( $Cpanel::appname eq 'webmail' ) {
        return $Cpanel::authuser;
    }
    elsif ( $ENV{'TEAM_USER'} ) {
        return "$ENV{'TEAM_USER'}\@$ENV{'TEAM_OWNER'}";
    }
    return $Cpanel::user;
}
1;
