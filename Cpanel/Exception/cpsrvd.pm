package Cpanel::Exception::cpsrvd;

# cpanel - Cpanel/Exception/cpsrvd.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Exception::cpsrvd

=head1 SYNOPSIS

(This class is not instantiated directly.)

=head1 DESCRIPTION

This is a base class for exceptions that are cpsrvd-specific.
It’s useful for cpsrvd to identify its own errors and handle
them accordingly.

=head1 INDICATING HTTP STATUS

If cpsrvd catches an exception that is an instance of this
base class and has an C<HTTP_STATUS_CODE> method, then
cpsrvd will send the appropriate response for that status
code.

=head1 INDICATING EXTRA HTTP HEADERS

You can create an C<_extra_headers()> method in the subclass
that returns a list of:

    ( [ $header => $value ], .. )

=cut

#----------------------------------------------------------------------

use parent qw( Cpanel::Exception );

use Cpanel::HTTP::StatusCodes ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 @headers = I<OBJ>->extra_headers()

A passthrough to the C<_extra_headers()> method described above.

=cut

sub extra_headers ($self) {
    return $self->_extra_headers();
}

sub _default_phrase {
    my ($self) = @_;

    my $reason = $Cpanel::HTTP::StatusCodes::STATUS_CODES{ $self->HTTP_STATUS_CODE() };

    return sprintf "HTTP %d: %s", $self->HTTP_STATUS_CODE(), $reason;
}

# Optionally overridden in subclasses:
sub _extra_headers {
    return;
}

1;
