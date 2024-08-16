package Whostmgr::API::1::CORSProxy;

# cpanel - Whostmgr/API/1/CORSProxy.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Whostmgr::API::1::Utils ();
use Cpanel::Sys::Hostname   ();

use constant NEEDS_ROLE => {
    cors_proxy_get => undef,
};

my $http;

sub cors_proxy_get {
    my ( $args, $metadata ) = @_;

    require Cpanel::HTTP::Client;
    $http ||= Cpanel::HTTP::Client->new();

    # CORS requires all cross-origin requests to contain an Origin header
    my $https  = $ENV{HTTPS} && $ENV{HTTPS} =~ m/on/i ? 1          : 0;
    my $origin = $https                               ? 'https://' : 'http://';
    $origin .=
        $ENV{HOST}        ? $ENV{HOST}
      : $ENV{SERVER_NAME} ? $ENV{SERVER_NAME}
      :                     Cpanel::Sys::Hostname::gethostname();

    $origin .= $ENV{SERVER_PORT} ? ":$ENV{SERVER_PORT}" : $https ? ":2087" : ":2086";

    my $res = $http->get( $args->{url}, { headers => { origin => $origin } } );    # throws an exception if URL is invalid

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return { %{$res} };                                                            # unbless the Cpanel::HTTP::Client::Response object
}

1;

__END__

=encoding utf8

=head1 NAME

Whostmgr::API::1::CORSProxy - Enable WHM to act as a same-origin CORS Proxy

=head1 SYNOPSIS

Works like all Whostmgr::API::1 modules.

    use Whostmgr::API::1::CORSProxy ();

    my $url = "https://some.other.domain.example.com/api/v1/service/livechat/status";
    my $res = Whostmgr::API::1::CORSProxy::cors_proxy_get({url => $url}, $metadata);

    if ($res->{success}) {
        # $res->{content} contains the JSON that `GET $url` returned
        _consume_livechat_status_api_call_JSON($res->{content});
    }
    else {
        warn "The request for live chat status failed: $res->{status} $res->{reason}\n";
    }

=head1 DESCRIPTION

This allows WHM web applications to use AJAX to get resources from other servers that would otherwise not be allowed due to CORS restrictions.

Even if the remote server sends Access-Control-Allow-Origin (and other Access-Control-*) it can still fail for users whose browsers are behind a firewall that strips those headers.

=head1 INTERFACE

=head2 cors_proxy_get()

Takes a URL, via a single C<url> param, and does a C<GET> request for it.

Returns a L<Cpanel::HTTP::Client::Response> object hash.

Always check the response's content type header (C<$res-E<gt>{headers}{'content-type'}>) before operating on C<content>.

=head2 What about other HTTP Methods?

Others can be added if needed after proper evaluation. The pattern to use is C<cors_proxy_$method>.

e.g. C<cors_proxy_get> for C<GET>, C<cors_proxy_post()> for C<POST>, etc

=head1 DIAGNOSTICS

If the URL is not valid the API call will return failure.

Otherwise this throws no errors or warnings of its own. The L<Cpanel::HTTP::Client::Response> object has will contain information about success, failure, content, and other info you may need.
