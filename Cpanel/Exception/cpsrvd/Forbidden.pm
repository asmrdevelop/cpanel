package Cpanel::Exception::cpsrvd::Forbidden;

# cpanel - Cpanel/Exception/cpsrvd/Forbidden.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Exception::cpsrvd::Forbidden

=head1 SYNOPSIS

    die Cpanel::Exception::create('cpsrvd::Forbidden');

=head1 DESCRIPTION

This exception is useful when a service (e.g., a WebSocket application)
wants to fail authorization. cpsrvd will catch this exception and convert
it into an HTTP 403 (Forbidden) response.

The exception’s phrase will be sent in the HTTP response body. (The
default phrase probably suffices for most cases.)

=cut

use parent qw( Cpanel::Exception::cpsrvd );

use Cpanel::LocaleString ();

use constant HTTP_STATUS_CODE => 403;

sub _default_phrase {
    return Cpanel::LocaleString->new('You lack the required privilege to access this resource.');
}

1;
