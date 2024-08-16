package Cpanel::Exception::cpsrvd::NotAcceptable;

# cpanel - Cpanel/Exception/cpsrvd/NotAcceptable.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Exception::cpsrvd::NotAcceptable

=head1 SYNOPSIS

    die Cpanel::Exception::create_raw('cpsrvd::NotAcceptable', 'This is why.');

=head1 DESCRIPTION

This exception is useful when the HTTP request’s C<Accept> header excludes
all of the content types that the server can send in response to the request.

=cut

use parent qw( Cpanel::Exception::cpsrvd );

use constant HTTP_STATUS_CODE => 406;

sub _default_phrase {
    return 'Content negotiation failed; check the request’s “Accept” header.';
}

1;
