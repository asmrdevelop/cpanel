package Cpanel::Template::Plugin::HTTP;

# cpanel - Cpanel/Template/Plugin/HTTP.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Template::Plugin::HTTP - cPanel’s HTTP-centric template plugin

=cut

#----------------------------------------------------------------------

use parent 'Template::Plugin';

use Cpanel::HTTP::QueryString ();

#----------------------------------------------------------------------

=head1 METHODS

=cut

sub STATUS_CODES {
    require Cpanel::HTTP::StatusCodes;
    return \%Cpanel::HTTP::StatusCodes::STATUS_CODES;
}

sub parse {
    shift;
    require Cpanel::JSON;
    goto \&Cpanel::JSON::Load;
}

sub make_query_string {
    return Cpanel::HTTP::QueryString::make_query_string( $_[1] );
}

=head2 url = get_client_url( $REQUEST_URI )

A wrapper around L<Cpanel::CGI::URL>’s function of the same name.

=cut

sub get_client_url ( $self, $request_uri = undef ) {
    require Cpanel::CGI::URL;
    return Cpanel::CGI::URL::get_client_url($request_uri);
}

1;
