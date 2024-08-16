package Cpanel::Sys::Hostname::FQDN;

# cpanel - Cpanel/Sys/Hostname/FQDN.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#
use strict;
use warnings;

use Cpanel::Sys::Hostname::Fallback ();
use Cpanel::Sys::Uname              ();

=encoding utf-8

=head1 NAME

Cpanel::Sys::Hostname::FQDN - Fetch the hostname from multiple source to determine the FQDN

=head1 SYNOPSIS

    use Cpanel::Sys::Hostname::FQDN ();

    my $hostname = Cpanel::Sys::Hostname::FQDN::get_fqdn_hostname();

    my $shorthostname = Cpanel::Sys::Hostname::FQDN::get_short_hostname();

=head1 DESCRIPTION

Use multiple sources to determine the FQDN hostname

=head2 get_fqdn_hostname()

This will look at the result of uname() and
getnameinfo() to determine the FQDN hostname

=cut

sub get_fqdn_hostname {
    my $hostname_from_uname = ( Cpanel::Sys::Uname::get_uname_cached() )[1];
    $hostname_from_uname =~ tr{A-Z}{a-z};

    my $hostname_from_getnameinfo = Cpanel::Sys::Hostname::Fallback::get_canonical_hostname();

    if ( !length $hostname_from_getnameinfo ) {
        return $hostname_from_uname;
    }

    $hostname_from_getnameinfo =~ tr{A-Z}{a-z};

    if ( index( $hostname_from_getnameinfo, $hostname_from_uname ) == 0 ) {
        return $hostname_from_getnameinfo;
    }

    return $hostname_from_uname;
}

sub get_short_hostname {
    return ( split( /\./, get_fqdn_hostname() ) )[0];
}

1;
