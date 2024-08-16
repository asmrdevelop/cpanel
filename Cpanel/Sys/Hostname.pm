package Cpanel::Sys::Hostname;

# cpanel - Cpanel/Sys/Hostname.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our $VERSION = 2.0;

use Cpanel::Sys::Uname ();

our $cachedhostname = '';

################################################################################
# gethostname
# return hostname if found in server configuration, use cached result
# NOTE: This will overwrite $@, so take care if calling it within a DESTROY.
################################################################################
sub gethostname {
    my $nocache = shift || 0;
    if ( !$nocache && length $cachedhostname ) { return $cachedhostname }

    my $hostname = _gethostname($nocache);

    if ( length $hostname ) {
        $hostname =~ tr{A-Z}{a-z};    # hostnames must be lowercase (see Cpanel::Sys::Hostname::Modify::make_hostname_lowercase_fqdn)
        $cachedhostname = $hostname;
    }
    return $hostname;
}

################################################################################
# _gethostname
# return hostname if found in server configuration
################################################################################
sub _gethostname {
    my $nocache = shift || 0;

    my $hostname;
    Cpanel::Sys::Uname::clearcache() if $nocache;
    my @uname = Cpanel::Sys::Uname::get_uname_cached();
    if ( $uname[1] && index( $uname[1], '.' ) > -1 ) {
        $hostname = $uname[1];
        $hostname =~ tr{A-Z}{a-z};    # hostnames must be lowercase (see Cpanel::Sys::Hostname::Modify::make_hostname_lowercase_fqdn)
        return $hostname;
    }

    eval {
        require Cpanel::Sys::Hostname::Fallback;
        $hostname = Cpanel::Sys::Hostname::Fallback::get_canonical_hostname();
    };
    if ($hostname) {
        $hostname =~ tr{A-Z}{a-z};    # hostnames must be lowercase (see Cpanel::Sys::Hostname::Modify::make_hostname_lowercase_fqdn)
        return $hostname;
    }

    require Cpanel::LoadFile;
    chomp( $hostname = Cpanel::LoadFile::loadfile( '/proc/sys/kernel/hostname', { 'skip_exists_check' => 1 } ) );
    if ($hostname) {
        $hostname =~ tr{A-Z}{a-z};    # hostnames must be lowercase (see Cpanel::Sys::Hostname::Modify::make_hostname_lowercase_fqdn)
        $hostname =~ tr{\r\n}{}d;     # chomp is not enough (not sure if this is required, however we cannot test all kernels so its safer to leave it in)
        return $hostname;
    }

    require Cpanel::Debug;
    Cpanel::Debug::log_warn('Unable to determine correct hostname');
    return;
}

################################################################################
# shorthostname
################################################################################

sub shorthostname {
    my $hostname = gethostname();
    return $hostname if index( $hostname, '.' ) == -1;    # Hostname is not a FQDN (this should never happen)
    return substr( $hostname, 0, index( $hostname, '.' ) );
}

1;
