package Cpanel::WebVhosts::Owner;

# cpanel - Cpanel/WebVhosts/Owner.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::WebVhosts::Owner

=head1 DISCUSSION

Obtain the owner of a web vhost.

=head1 SYNOPSIS

    my $vhost_name = Cpanel::WebVhosts::Owner::get_vhost_name_for_domain_or_undef('koston.org');

=cut

#----------------------------------------------------------------------

use Cpanel::Domain::Owner ();

#----------------------------------------------------------------------

=head2 $VH_NAME = get_vhost_name_for_domain_or_undef($DOMAIN)

Returns the name of $DOMAIN’s web vhost. If no such vhost can be found,
returns undef.

B<NOTE:> If you already know the domain’s owner, then just load
L<Cpanel::Config::WebVhosts> and query using an instance of that class.

=cut

sub get_vhost_name_for_domain_or_undef {
    return _get_vhost_name_for_domain( shift, 'get_owner_or_undef' );
}

sub _get_vhost_name_for_domain {
    my ( $domain, $get_owner_fn ) = @_;

    my $vh_name;

    my $get_owner_cr = Cpanel::Domain::Owner->can($get_owner_fn);

    my $domain_owner = $get_owner_cr->($domain) || 'nobody';

    require Cpanel::Config::WebVhosts;
    my $wvh = Cpanel::Config::WebVhosts->load($domain_owner);

    $vh_name = $wvh->get_vhost_name_for_domain($domain);
    $vh_name ||= $wvh->get_vhost_name_for_ssl_proxy_subdomain($domain);

    return $vh_name;
}

1;
