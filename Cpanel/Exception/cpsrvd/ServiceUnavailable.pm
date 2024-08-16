package Cpanel::Exception::cpsrvd::ServiceUnavailable;

# cpanel - Cpanel/Exception/cpsrvd/ServiceUnavailable.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Exception::cpsrvd::ServiceUnavailable

=head1 SYNOPSIS

    die Cpanel::Exception::create_raw('cpsrvd::ServiceUnavailable', 'This is why.');

=head1 DESCRIPTION

This exception tells cpsrvd to fail the client’s request with an HTTP 503
(Service Unavailable) response.

The exception’s phrase will be sent in the HTTP response body. The
default phrase isn’t very helpful, so you should give your own when
throwing this exception.

=cut

use parent qw( Cpanel::Exception::cpsrvd );

use Cpanel::LocaleString ();

use constant HTTP_STATUS_CODE => 503;

sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new('This host is currently not available.');
}

1;
