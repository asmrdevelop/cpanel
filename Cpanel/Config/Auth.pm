package Cpanel::Config::Auth;

# cpanel - Cpanel/Config/Auth.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Config::LoadConfig ();
use Cpanel::OS                 ();

our $VERSION              = 1.1;
our $sysconfig_authconfig = '/etc/sysconfig/authconfig';

our $cached_passwd_algorithm;

sub _pam_system_auth() {
    return '/etc/pam.d/' . Cpanel::OS::pam_file_controlling_crypt_algo();
}

sub fetch_system_passwd_algorithm() {
    return $cached_passwd_algorithm if defined $cached_passwd_algorithm;

    if ( -e _pam_system_auth() ) {
        my $authcfg = Cpanel::Config::LoadConfig::loadConfig( $sysconfig_authconfig, undef, '=' );
        if ( ref $authcfg && exists $authcfg->{'PASSWDALGORITHM'} && $authcfg->{'PASSWDALGORITHM'} =~ m/^(sha512|sha256|md5)$/ ) {
            return ( $cached_passwd_algorithm = $1 );
        }
    }
    my $password_regex = qr/^[\s\t]*password.*/;
    if ( open( my $pam_fh, '<', _pam_system_auth() ) ) {
        while ( defined( my $line = readline($pam_fh) ) ) {
            if ( $line =~ m/$password_regex\b(sha512|sha256|md5)\b/ ) {
                return ( $cached_passwd_algorithm = $1 );
            }
        }
        close($pam_fh);
    }
    return '';
}

1;
