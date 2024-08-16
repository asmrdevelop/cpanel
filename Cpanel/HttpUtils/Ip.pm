package Cpanel::HttpUtils::Ip;

# cpanel - Cpanel/HttpUtils/Ip.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 FUNCTIONS

=head2 $ip = get_domain_ip( $DOMAIN_NAME )

Returns the IPv4 address of $DOMAIN_NAME’s non-SSL web vhost. Note that,
due to the possibility of custom edits to web vhost configurations
(i.e., F</var/cpanel/userdata> files), this is not necessarily the same
as the IPv4 address of the user who owns $DOMAIN_NAME.

If the operating user has no access to an SSL web vhost for $DOMAIN_NAME,
then undef is returned.

If no user on the system owns $DOMAIN_NAME, then an exception is thrown.

B<NOTE:> This function can be called as root or as a user, but if
you know you’re running as a user, you might as well use
L<Cpanel::UserDomainIp> rather than this module.

=cut

#----------------------------------------------------------------------

use Cpanel::UserDomainIp ();

our $VERSION = '1.2';

=head1 FUNCTIONS

=head2 $ip = get_domain_ip( $DOMAIN_NAME )

Returns the IPv4 address of $DOMAIN_NAME’s non-SSL web vhost. Note that,
due to the possibility of custom edits to web vhost configurations
(i.e., F</var/cpanel/userdata> files), this is not necessarily the same
as the IPv4 address of the user who owns $DOMAIN_NAME.

If the operating user has no access to an SSL web vhost for $DOMAIN_NAME,
then undef is returned.

If no user on the system owns $DOMAIN_NAME, then an exception is thrown.

B<NOTE:> This function can be called as root or as a user, but if
you know you’re running as a user, you might as well use
L<Cpanel::UserDomainIp> rather than this module.

=cut

sub get_domain_ip {
    my ($domain_name) = @_;

    return _get_ip( 'getdomainip', $domain_name );
}

=head2 $ip = get_ssl_domain_ip( $DOMAIN_NAME )

Like C<get_domain_ip()>, but this checks the SSL web vhost.

=cut

sub get_ssl_domain_ip {
    my ($domain_name) = @_;

    return _get_ip( 'getdomainip_ssl', $domain_name );
}

sub _get_ip {
    my ( $udi_fn, $domain_name ) = @_;

    die "Need domain name!" if !length $domain_name;

    my $username;

    if ( !$> ) {
        require Cpanel::Domain::Owner;
        $username = Cpanel::Domain::Owner::get_owner_or_die($domain_name);
    }

    local $Cpanel::user = $username if defined $username;

    return Cpanel::UserDomainIp->can($udi_fn)->($domain_name);
}

#----------------------------------------------------------------------

=head2 $ip = getipfromdomain( $DOMAIN_NAME, $TIMEOUT, $ALLOW_RESOLVER )

Like C<get_domain_ip()>, but this adds a fallback to a DNS resolver if
$ALLOW_RESOLVER is truthy. $TIMEOUT is in seconds and is useless if
!$ALLOW_RESOLVER.

=cut

sub getipfromdomain {
    my ( $domain, $timeout, $allow_fallback_to_resolver ) = @_;

    my $ip = get_domain_ip($domain);

    if ( $allow_fallback_to_resolver && !length $ip ) {
        require Cpanel::SocketIP;
        $ip = Cpanel::SocketIP::_resolveIpAddress( $domain, 'timeout' => $timeout );
    }

    return $ip;
}

1;
