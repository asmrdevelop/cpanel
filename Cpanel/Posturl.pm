package Cpanel::Posturl;

# cpanel - Cpanel/Posturl.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::HTTP::QueryString         ();
use Cpanel::HTTP::Tiny::FastSSLVerify ();

sub new {
    my ($class) = @_;
    return bless { '_http_tiny_obj' => Cpanel::HTTP::Tiny::FastSSLVerify->new() }, $class;

}

###########################################################################
#
# Method:
#   post
#
# Description:
#   This method HTTP POSTs data to a supplied URL.
#
# Exceptions:
#   Die messages from HTTP::Tiny may be thrown on some failures.
#
# Returns:
#   Returns a hashref from a HTTP::Tiny::request call
#   cf. https://metacpan.org/pod/HTTP::Tiny#request
#
sub post {
    my ( $self, $url, $post_ref ) = @_;

    my ( $post_url, $query_string ) = split( m{\?}, $url, 2 );    # Allow them to provide an api token on the querystring, however convert it to a POST for security
    my $parsed = Cpanel::HTTP::QueryString::parse_query_string_sr( \$query_string );
    return $self->{'_http_tiny_obj'}->post_form(
        $post_url,
        {
            %$parsed,
            %$post_ref,
        },
        {

            'headers' => { 'Content-type' => 'application/x-www-form-urlencoded; charset=UTF-8' },
        }
    );
}

1;
