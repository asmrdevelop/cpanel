package Cpanel::Cron::Edit;

# cpanel - Cpanel/Cron/Edit.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Try::Tiny;

use Cpanel::Config::LoadConfig ();
use Cpanel::Context            ();
use Cpanel::Cron::Utils        ();
use Cpanel::Exception          ();
use Cpanel::Features::Check    ();
use Cpanel::Locale             ();
use Cpanel::Logger             ();
use Cpanel::Validate::Username ();

our $CRONTAB_SHELL_FILE;
*CRONTAB_SHELL_FILE = \$Cpanel::Cron::Utils::CRONTAB_SHELL_FILE;

our $CRON_ALLOW = '/etc/cron.allow';
our $CRON_DENY  = '/etc/cron.deny';

my $logger = Cpanel::Logger->new();

my $locale;

sub _locale {
    return $locale ||= Cpanel::Locale->get_handle();
}

sub _run_crontab_command {
    my @run_args = @_;

    my ( $resp, $err );

    try {
        $resp = Cpanel::Cron::Utils::run_crontab(@run_args);
    }
    catch {
        $err = $_;
    };

    return ( 0, Cpanel::Exception::get_string($err) ) if $err;

    return ( 1, $resp );
}

#NOTE: Prefer the one in Cpanel::Cron::Utils (or ::User) for new code.
sub fetch_user_cron {
    my ($user) = @_;

    my ( $username_ok, $username_msg ) = validate_username($user);
    return ( 0, $username_msg ) if !$username_ok;

    my ( $run_ok, $run ) = _run_crontab_command(
        args => [
            '-u' => $user,
            '-l',
        ],
    );

    if ($run_ok) {
        return ( 1, $run->stdout() );
    }

    return ( $run_ok, $run );
}

#NOTE: By this point we assume that the user has the cron feature.
#This does, though, verify the username and the crontab contents themselves.
#NOTE: Prefer the one in Cpanel::Cron::Utils (or ::User) for new code.
sub save_user_cron {
    my ( $user, $crontab_sr ) = @_;

    if ( !ref $crontab_sr ) {
        $crontab_sr = \"$crontab_sr";
    }

    my ( $username_ok, $username_msg ) = validate_username($user);
    return ( 0, $username_msg ) if !$username_ok;

    my ( $fix_ok, $fix_err ) = fix_user_crontab( $user, $crontab_sr );
    return ( 0, $fix_err ) if !$fix_ok;

    my ( $run_ok, $run ) = _run_crontab_command(
        args => [
            '-u' => $user,
            '-',
        ],
        stdin => $crontab_sr,
    );

    return $run_ok || ( 0, $run );
}

#XXX Do not use in new code; prefer the one in Cpanel::Cron::Utils.
sub fix_user_crontab {
    my ( $username, $crontab_sr ) = @_;

    Cpanel::Context::must_be_list();

    my ( $ret, $err );
    try {
        $ret = Cpanel::Cron::Utils::fix_user_crontab( $username, $crontab_sr );
    }
    catch {
        $err = $_;
    };

    return ( 0, Cpanel::Exception::get_string($err) ) if $err;

    return ( 1, $ret );
}

sub validate_username {
    my ($username) = @_;

    if ( !Cpanel::Validate::Username::is_valid($username) ) {
        return ( 0, _locale()->maketext( '“[_1]” is not a valid username.', $username ) );
    }

    return 1;
}

sub user_is_permitted_to_use_crontab {
    my ($user) = @_;

    if ( $user ne 'root' ) {

        my $has_cron_feature = Cpanel::Features::Check::check_feature_for_user( $user, 'cron' );

        if ( -e $CRON_ALLOW ) {

            my $cron_allow_ref = Cpanel::Config::LoadConfig::loadConfig( $CRON_ALLOW, undef, '' );

            if ( !$cron_allow_ref ) {
                return ( 0, _locale()->maketext( 'The system failed to load the file “[_1]” because of an error: [_2]', $CRON_ALLOW, $! ) );
            }

            # When using cron.allow, only grant permission if they are listed in the cron.allow file and also have the feature enabled.
            if ( exists $cron_allow_ref->{$user} && $has_cron_feature ) {
                return ( 1, 1 );
            }
            else {
                return ( 1, 0 );
            }

        }

        if ( -e $CRON_DENY ) {

            my $cron_deny_ref = Cpanel::Config::LoadConfig::loadConfig( $CRON_DENY, undef, '' );

            if ( !$cron_deny_ref ) {
                return ( 0, _locale()->maketext( 'The system failed to load the file “[_1]” because of an error: [_2]', $CRON_DENY, $! ) );
            }

            # When using cron.deny, deny permission if they are listed in cron.deny or if they do not have the feature enabled.
            if ( exists $cron_deny_ref->{$user} || !$has_cron_feature ) {
                return ( 1, 0 );
            }
            else {
                return ( 1, 1 );

            }
        }

        # neither cron file is in use, permission is based solely on the cron feature being enabled.
        return ( 1, $has_cron_feature );
    }

    # root always has permission
    return ( 1, 1 );

}

1;
