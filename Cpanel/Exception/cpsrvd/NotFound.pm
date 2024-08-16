package Cpanel::Exception::cpsrvd::NotFound;

# cpanel - Cpanel/Exception/cpsrvd/NotFound.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Exception::cpsrvd::NotFound

=head1 SYNOPSIS

    die Cpanel::Exception::create_raw('cpsrvd::NotFound', 'This is why.');

=head1 DESCRIPTION

This exception is useful when a service (e.g., a SSE application)
wants to fail a request because the requested resource was not found.
cpsrvd will catch this exception and convert it into an HTTP 404
(Not Found) response.

The exception’s phrase will be sent in the HTTP response body. The
default phrase isn’t very helpful, so you should give your own when
throwing this exception.

=cut

use parent qw( Cpanel::Exception::cpsrvd );

use Cpanel::LocaleString ();

use constant HTTP_STATUS_CODE => 404;

sub _default_phrase {
    return Cpanel::LocaleString->new('The system could not find the requested resource.');
}

1;
