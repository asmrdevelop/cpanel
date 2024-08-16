package Cpanel::HTTP::Client;

# cpanel - Cpanel/HTTP/Client.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::HTTP::Client - cPanel’s standard Perl HTTP client

=head1 SYNOPSIS

    use Cpanel::HTTP::Client;

    my $http = Cpanel::HTTP::Client->new();

    # Do this unless you’re handling 4xx and 5xx responses yourself:
    $http->die_on_http_error();

    # NOTE: Unlike HTTP::Tiny::UA’s method, this will die() if the HTTP
    # session itself fails--for example, if the network connection was
    # interrupted.
    my $resp_obj = $http->post_form( $the_url, \%the_form_post );

    my $content = $resp_obj->content();

=head1 DESCRIPTION

This module extends L<Cpanel::HTTP::Tiny::FastSSLVerify> (itself
a subclass of CPAN’s L<HTTP::Tiny>) and adds the following useful bits:

=over

=item * C<request()> and related methods will return
L<Cpanel::HTTP::Client::Response> instances rather than plain hashes.

=item * L<Cpanel::Exception::HTTP::Network> objects are thrown rather than
HTTP::Tiny’s “return-in-failure” (HTTP 599) behavior.

You may—and probably should—additionally enable exceptions whenever the
HTTP response is 4xx or 5xx by calling C<die_on_http_error()> (see above).

=item * Uses L<Cpanel::HTTP::Tiny::FastSSLVerify> under the hood for
optimal resource usage when using SSL/TLS.

=item * C<$@> is preserved, which helps to avoid action-at-a-distance bugs
related to that variable.

=back

=cut

use strict;

my %MODULE_PARAMS;

use parent qw(
  Cpanel::HTTP::Tiny::FastSSLVerify
);

use Cpanel::Exception              ();
use Cpanel::HTTP::Client::Response ();

our $VERSION = '1.0';

#----------------------------------------------------------------------

=head1 METHODS

Besides the stuff inherited from L<Cpanel::HTTP::Tiny::FastSSLVerify>:

=cut

# nothing remarkable added here:
sub new {
    my ( $class, @args ) = @_;

    my $self = $class->SUPER::new(@args);

    $MODULE_PARAMS{$self} = {};

    return $self;
}

=head2 $obj = I<OBJ>->die_on_http_error()

Enables L<Cpanel::Exception::HTTP::Server> exceptions on HTTP 4xx and
5xx responses.

=cut

sub die_on_http_error {
    my ($self) = @_;

    $MODULE_PARAMS{$self}{'die_on_http_error'} = 1;

    return $self;
}

=head2 $obj = I<OBJ>->return_on_http_error()

Undoes C<die_on_http_error()> (above).

=cut

sub return_on_http_error {
    my ($self) = @_;

    $MODULE_PARAMS{$self}{'die_on_http_error'} = 0;

    return $self;
}

# nothing new added to the interface
sub request {
    my ( $self, $method, $url, $args_hr ) = @_;

    #HTTP::Tiny clobbers this. The clobbering is useless since the
    #error is in the $resp variable already. Clobbering also risks
    #action-at-a-distance problems, so prevent it here.
    local $@;

    my $resp = $self->SUPER::request( $method, $url, $args_hr || () );

    my $resp_obj = Cpanel::HTTP::Client::Response->new($resp);

    #cf. HTTP::Tiny docs
    if ( $resp_obj->status() == 599 ) {
        my $error = $resp_obj->content();

        # Make sure error messages from HTTP::Tiny
        # have the trailing \n stripped
        chomp($error) if $error && !ref $error;
        die Cpanel::Exception::create(
            'HTTP::Network',
            [
                method    => $method,
                url       => $url,
                error     => $error,
                redirects => $resp_obj->redirects(),
            ]
        );
    }

    if ( $MODULE_PARAMS{$self}{'die_on_http_error'} && $resp->{'status'} >= 400 ) {
        die Cpanel::Exception::create(
            'HTTP::Server',
            [
                method       => $method,
                content_type => scalar( $resp_obj->header('Content-Type') ),
                ( map { ( $_ => $resp_obj->$_() ) } qw( content status reason url headers redirects ) ),
            ],
        );
    }

    return $resp_obj;
}

=head2 set_default_header( $header_name, $header_value )

Adds a default header to all HTTP requests.

Returns 1.

=cut

# XXX: WARNING: This could break if HTTP::Tiny changes where
# default_headers are stored.
sub set_default_header {
    my ( $self, $header, $value ) = @_;
    $header =~ tr/[A-Z]/[a-z]/;
    $self->{'default_headers'}{$header} = $value;
    return 1;
}

=head2 delete_default_header( $header )

Removes a default header previously added via
C<set_default_header()>.

Returns the previous value for the header, or undef if no
such header was set.

=cut

# XXX: WARNING: This could break if HTTP::Tiny changes where
# default_headers are stored.
sub delete_default_header {
    my ( $self, $header ) = @_;

    $header =~ tr/[A-Z]/[a-z]/;
    return delete $self->{'default_headers'}{$header};
}

sub DESTROY {
    my ($self) = @_;
    delete $MODULE_PARAMS{$self};

    $self->SUPER::DESTROY() if $self->can('SUPER::DESTROY');

    return;
}

=head1 SEE ALSO

L<HTTP::Tiny>’s purpose is more to facilitate Perl’s access to CPAN rather
than to be a general-purpose HTTP client for Perl applications. Thus, needs
may arise where this module isn’t the best fit.

The following are widely-used alternatives:

=over

=item * L<Net::Curl> - Perl binding to L<curl|https://curl.se>. In use
in cPanel & WHM for non-blocking HTTP requests. See L<Cpanel::NetCurlEasy>.

=item * L<LWP::UserAgent> - Similar to HTTP::Tiny but more general-purpose.

=item * L<Mojo::UserAgent> - Like LWP::UserAgent but part of the broader
L<Mojolicious> project. In limited use in cPanel & WHM.

=back

Before using one of these, please ensure that you truly I<need> the
alternative interface.

=cut

1;
