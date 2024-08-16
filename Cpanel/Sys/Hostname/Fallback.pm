package Cpanel::Sys::Hostname::Fallback;

# cpanel - Cpanel/Sys/Hostname/Fallback.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#
use strict;
use warnings;

use Socket             ();
use Cpanel::Sys::Uname ();

=encoding utf-8

=head1 NAME

Cpanel::Sys::Hostname::Fallback - Fetch the hostname using getnameinfo()

=head1 SYNOPSIS

    use Cpanel::Sys::Hostname::Fallback ();

    my $hostname = Cpanel::Sys::Hostname::Fallback::get_canonical_hostname();

=head1 DESCRIPTION

We normally fetch the hostname by fetching uname() and returning
the 2nd value.  In the event this value is not a FQDN, the
Cpanel::Sys::Hostname::gethostname() function will load this
module in order to fetch the hostname using getnameinfo()

=head2 get_canonical_hostname()

Fetch the hostname using getnameinfo()

=cut

sub get_canonical_hostname {
    my @uname = Cpanel::Sys::Uname::get_uname_cached();
    my ( $err, @results ) = Socket::getaddrinfo( $uname[1], 0, { flags => Socket::AI_CANONNAME() } );
    if ( @results && $results[0]->{'canonname'} ) {
        return $results[0]->{'canonname'};
    }

    return undef;

}

1;
