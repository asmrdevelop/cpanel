package Cpanel::Exception::cpsrvd::InternalServerError;

# cpanel - Cpanel/Exception/cpsrvd/InternalServerError.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Exception::cpsrvd::InternalServerError

=head1 SYNOPSIS

    die Cpanel::Exception::create_raw('cpsrvd::InternalServerError', 'This is why.');

=head1 DESCRIPTION

This exception tells cpsrvd to fail the client’s request with an HTTP 500
(Internal Server Error) response.

Note that 500 is a generic, non-descript “the problem is on my end”;
if a more specific 5xx error code can be used to represent the problem,
that will probably be more useful.

The exception’s phrase will be sent in the HTTP response body. The
default phrase isn’t very helpful, so you should give your own when
throwing this exception.

=cut

use parent qw( Cpanel::Exception::cpsrvd );

use constant HTTP_STATUS_CODE => 500;

1;
