package Cpanel::API::WebVhosts;

# cpanel - Cpanel/API/WebVhosts.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::API::WebVhosts - API Functions related to WebVhosts

=head1 SYNOPSIS

    use Cpanel::API ();

    my $result = Cpanel::API::execute_or_die( 'WebVhosts', 'list_domains', \%args );
    my $domains = $result->data();

=head1 DESCRIPTION

    API Functions related to WebVhosts

=cut

use strict;
use warnings;

use Cpanel            ();
use Cpanel::WebVhosts ();

=head2 list_domains

Returns list of domains for the current user ($Cpanel::user)
Data comes from Cpanel::WebVhosts::list_domains

This API call takes no inputs.

The return is a list of hashes, one per domain, like:

    [
        {
            vhost_name => '...',
            domain => '...',
            vhost_is_ssl => 0 or 1,

            #Present only when vhost_is_ssl is true.
            #Contents vary according to configuration.
            proxy_subdomains => [ 'cpanel', 'webmail' ],
        },
        ...
    ]

=cut

sub list_domains {
    my ( $args, $result ) = @_;

    $result->data( [ Cpanel::WebVhosts::list_domains($Cpanel::user) ] );

    return 1;
}

=head2 list_ssl_capable_domains

Returns a list of all domains that can receive an SSL certificate for the current user ($Cpanel::user)
Data comes from Cpanel::WebVhosts::list__ssl_domains

This API call takes no inputs.

The return is a list of hashes, one per domain, like:

    [
        {
            domain => '...',
            vhost_name => '...',
            is_proxy => 0 or 1,
        },
        ...
    ]

=cut

sub list_ssl_capable_domains {
    my ( $args, $result ) = @_;

    $result->data( [ Cpanel::WebVhosts::list_ssl_capable_domains($Cpanel::user) ] );

    return 1;
}

my $allow_demo = { allow_demo => 1 };

our %API = (
    list_domains             => $allow_demo,
    list_ssl_capable_domains => $allow_demo,
);

1;
