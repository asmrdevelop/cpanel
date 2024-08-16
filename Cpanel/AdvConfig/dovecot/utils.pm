package Cpanel::AdvConfig::dovecot::utils;

# cpanel - Cpanel/AdvConfig/dovecot/utils.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::ConfigFiles   ();
use Cpanel::CachedCommand ();

use constant DEFAULT_VERSION => '2.3.13';

sub get_dovecot_version() {

    my $bin = find_dovecot_bin();

    # advertise the default version when not installed
    return DEFAULT_VERSION unless -x $bin;

    my $string = Cpanel::CachedCommand::cachedcommand( $bin, '--version' );
    my ($version) = ( split( m{ }, $string ) )[0];
    $version ||= DEFAULT_VERSION;

    return $version;
}

sub find_dovecot_conf() {

    # If we are upgrading from 2.2.x to 2.3.x this would spew
    # because the builddovecotconf script calls find_dovecot_conf
    # so we now supress errors
    my $config_string = Cpanel::CachedCommand::cachedcommand_no_errors( find_dovecot_bin(), '-n' );
    if ( $config_string =~ /\s*#\s+[^:]+: (\S+)/m ) {
        return $1;
    }
    return '/etc/dovecot/dovecot.conf';
}

sub find_dovecot_auth_policy_conf() {
    return '/etc/dovecot/auth_policy.conf';
}

sub find_dovecot_sni_conf() {
    return $Cpanel::ConfigFiles::DOVECOT_SNI_CONF;
}

sub find_dovecot_ssl_conf() {
    return $Cpanel::ConfigFiles::DOVECOT_SSL_CONF;
}

sub find_dovecot_bin() {
    return '/usr/sbin/dovecot';
}

1;
