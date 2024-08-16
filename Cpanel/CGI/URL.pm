package Cpanel::CGI::URL;

# cpanel - Cpanel/CGI/URL.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::CGI::URL - Logic for URLs in a CGI context

=head1 SYNOPSIS

    if (Cpanel::CGI::URL::port_is_well_known()) {
        # ...
    }

    my $url_from_browser = Cpanel::CGI::URL::get_client_url();

=cut

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $yn = port_is_well_known()

Returns a boolean tha indicates whether the C<SERVER_PORT> is a well-known
TCP port.

This is subtly different from whether it’s a standard I<HTTP>
port since, theoretically, there could be introduced a new well-known TCP
port for HTTP/HTTPS, but for practical purposes that seems extremely
unlikely.

=cut

sub port_is_well_known() {
    return ( $ENV{'SERVER_PORT'} < 1024 );
}

=head2 $url = get_client_url( $REQUEST_URI )

Makes a “best-effort” guess, based on the standard CGI variables, at
reconstructing the original URL that would have been given to a client
(i.e., browser) to load the current HTTP resource.

This is much the same logic as C<CGI::url()> but accommodates cpsrvd’s
nonstandard treatment of CGI’s C<HTTP_HOST> environment variable.

$REQUEST_URI, if given, replaces the corresponding part of the URL—i.e.,
cpsrvd’s imitation of the same-named value from
L<mod_rewrite|https://httpd.apache.org/docs/current/mod/mod_rewrite.html>.
(This is useful for determining a return URL when redirecting away to
a linked node.)

=cut

sub get_client_url ( $request_uri = undef ) {
    if ( $request_uri && 0 != rindex( $request_uri, '/', 0 ) ) {
        die "REQUEST_URI ($request_uri) must start with “/”.";
    }

    return join(
        q<>,
        ( $ENV{'HTTPS'} && $ENV{'HTTPS'} eq 'on' ) ? 'https://' : 'http://',
        _guess_http_host(),
        $request_uri // $ENV{'REQUEST_URI'},
    );
}

#=head2 $val = guess_http_host()
#
#“Guesses” the HTTP C<Host> header by looking at the SERVER_PORT
#environment variable.
#
#=cut

sub _guess_http_host() {
    my $http_hostname = $ENV{'HTTP_HOST'} or die 'Need HTTP_HOST!';

    # A colon in HTTP_HOST means cpsrvd stopped stripping out the port.
    return $ENV{'HTTP_HOST'} if $http_hostname =~ s<:.*><>;

    return $http_hostname . ( port_is_well_known() ? q<> : ":$ENV{'SERVER_PORT'}" );
}

1;
