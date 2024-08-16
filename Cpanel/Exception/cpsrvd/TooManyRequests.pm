package Cpanel::Exception::cpsrvd::TooManyRequests;

# cpanel - Cpanel/Exception/cpsrvd/TooManyRequests.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Exception::cpsrvd::TooManyRequests

=head1 SYNOPSIS

    die Cpanel::Exception::create(
        'cpsrvd::TooManyRequests',
        [ retry_after => 3600 ],
    );

=head1 DESCRIPTION

This exception tells cpsrvd to send an HTTP “Too Many Requests” error
as the request response.

=head1 PROPERTIES

This exception recognizes the C<retry_after> property. cpsrvd converts it
into the corresponding HTTP response header.

=cut

use parent qw( Cpanel::Exception::cpsrvd );

use constant HTTP_STATUS_CODE => 429;

sub _extra_headers ($self) {
    my @hdrs;

    if ( my $retry_after = $self->get('retry_after') ) {
        push @hdrs, [ 'Retry-After' => $retry_after ];
    }

    return @hdrs;
}

1;
