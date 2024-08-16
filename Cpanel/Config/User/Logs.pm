package Cpanel::Config::User::Logs;

# cpanel - Cpanel/Config/User/Logs.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Config::LoadCpConf           ();
use Cpanel::Config::LoadConfig           ();
use Cpanel::AccessIds::ReducedPrivileges ();

sub load_users_log_config {
    my ( $pwent, $cpconf ) = @_;

    $cpconf ||= Cpanel::Config::LoadCpConf::loadcpconf();

    die "Failed to load cpanel.config" if !ref $cpconf;

    my $uid     = $pwent->[2];
    my $gid     = $pwent->[3];
    my $homedir = $pwent->[7];

    if ( -e $homedir . '/.cpanel-logs' ) {
        my $load_code_ref = sub { return scalar Cpanel::Config::LoadConfig::loadConfig( $homedir . '/.cpanel-logs' ); };
        my $user_conf_ref;
        if ( $> == 0 ) {
            $user_conf_ref = Cpanel::AccessIds::ReducedPrivileges::call_as_user( $load_code_ref, $uid, $gid );
        }
        else {
            $user_conf_ref = $load_code_ref->();
        }
        return ( ( $user_conf_ref->{'archive-logs'} ? 1 : 0 ), ( $user_conf_ref->{'remove-old-archived-logs'} ? 1 : 0 ) );
    }
    else {
        return ( ( $cpconf->{'default_archive-logs'} ? 1 : 0 ), ( $cpconf->{'default_remove-old-archived-logs'} ? 1 : 0 ) );
    }
}

1;
