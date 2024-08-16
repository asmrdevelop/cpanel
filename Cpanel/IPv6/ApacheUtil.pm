package Cpanel::IPv6::ApacheUtil;

# cpanel - Cpanel/IPv6/ApacheUtil.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::AcctUtils::Account           ();
use Cpanel::ConfigFiles::Apache::vhost   ();
use Cpanel::HttpUtils::ApRestart::BgSafe ();
use Cpanel::Locale                       ();
use Cwd                                  ();

my $locale;

#
# Add an ipv6 address to a user's configuration in the Apache config
#
sub add_ipv6_for_user {
    my ($user) = @_;

    $locale ||= Cpanel::Locale->get_handle();
    my ( $ret, $msg );

    if ( !Cpanel::AcctUtils::Account::accountexists($user) ) {
        return ( 0, $locale->maketext('Account does not exist.') );
    }

    # Update the apache config
    ( $ret, $msg ) = Cpanel::ConfigFiles::Apache::vhost::update_users_vhosts($user);
    return ( 0, $locale->maketext( "The system was unable to update the Apache configuration for “[_1]”: [_2]", $user, $msg ) ) unless $ret;

    # Restart apache so our changes take effect.
    Cpanel::HttpUtils::ApRestart::BgSafe::restart();

    return ( 1, $locale->maketext('OK') );
}

#
# Remove ipv6 from a user's apache configuration
#
sub remove_ipv6_for_user {
    my ($user) = @_;

    $locale ||= Cpanel::Locale->get_handle();
    my ( $ret, $msg );

    if ( !Cpanel::AcctUtils::Account::accountexists($user) ) {
        return ( 0, $locale->maketext('Account does not exist.') );
    }

    # Update the apache config
    ( $ret, $msg ) = Cpanel::ConfigFiles::Apache::vhost::update_users_vhosts($user);
    return ( 0, $locale->maketext( "The system was unable to update the Apache configuration for “[_1]”: [_2]", $user, $msg ) ) unless $ret;

    # Restart apache so our changes take effect.
    Cpanel::HttpUtils::ApRestart::BgSafe::restart();

    return ( 1, 'OK' );
}

1;
