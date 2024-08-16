package Whostmgr::Hostname::DNS;

# cpanel - Whostmgr/Hostname/DNS.pm                      Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::DIp::MainIP      ();
use Cpanel::DnsUtils::Exists ();
use Cpanel::NAT              ();
use Cpanel::ServerTasks      ();
use Cpanel::Sys::Hostname    ();
use Cpanel::Validate::IP     ();
use Whostmgr::DNS::Domains   ();

=encoding utf-8

=head1 NAME

Whostmgr::Hostname::DNS - Create a DNS entry for the hostname if one does not exist

=head1 SYNOPSIS

    use Whostmgr::Hostname::DNS;

    my($status,$statusmsg) = Whostmgr::Hostname::DNS::ensure_dns_for_hostname($ip);

=head2 ensure_dns_for_hostname($ip)

Creates a DNS zone for the hostname using the
provided IPv4 address if one does not already
exist.

=over 2

=item Input

=over 3

=item $ip C<SCALAR>

    The IPv4 address to use for the A entry.

=back

=item Output

=over 3

=item $status C<SCALAR>

    If the function is successful, the $status will
    be 1, otherwise the function will return a 0 $status.

=item $statusmsg C<SCALAR>

    A description of the result of the function call.

=back

=back

=cut

sub ensure_dns_for_hostname {
    my ($ip) = @_;

    # TODO: refactor this
    #
    # This code was moved from
    # whostmgr2 sub doaddaforhost
    #
    $ip ||= Cpanel::NAT::get_public_ip( Cpanel::DIp::MainIP::getmainserverip() );

    if ( !Cpanel::Validate::IP::is_valid_ip($ip) ) {
        return ( 0, 'Invalid IP Address Specified: ' . $ip );
    }
    my $hostname = Cpanel::Sys::Hostname::gethostname();
    if ( Cpanel::DnsUtils::Exists::domainexists($hostname) ) {
        return ( 1, "A DNS record already exists for “$hostname”." );
    }
    my ( $sub, $domain ) = split( /\./, $hostname, 2 );

    if ( Cpanel::DnsUtils::Exists::domainexists($domain) ) {
        my ( $status, $submsg ) = Whostmgr::DNS::Domains::addsubdomain( $sub, $domain, $ip );
        if ($status) {
            return ( 1, 'A Entry added for ' . $hostname . ' with address: ' . $ip );
        }
        return ( 0, ( $submsg || 'Failed to add the A Entry' ) );
    }

    require Cpanel::DnsUtils::Add;
    my ( $status, $status_msg ) = Cpanel::DnsUtils::Add::doadddns( 'domain' => $hostname, 'ip' => $ip, 'reseller' => $ENV{'REMOTE_USER'} );

    if ($status) {
        Cpanel::ServerTasks::queue_task( ['CpDBTasks'], 'update_userdomains' );
    }

    return ( $status, $status_msg );
}

1;
