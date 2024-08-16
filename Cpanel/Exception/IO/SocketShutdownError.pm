package Cpanel::Exception::IO::SocketShutdownError;

# cpanel - Cpanel/Exception/IO/SocketShutdownError.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Exception::IO::SocketShutdownError

=head1 SYNOPSIS

    Cpanel::Exception::create(
        'IO::SocketShutdownError',
        { error => $!, how => $how },
    );

=head1 DISCUSSION

You probably don’t want to instantiate this directly; instead, just use
C<Cpanel::Autodie::shutdown()>, and be happy. :)

=cut

use strict;
use warnings;

use parent qw( Cpanel::Exception::ErrnoBase );

use Cpanel::LocaleString      ();
use Cpanel::Socket::Constants ();

#Metadata propreties:
#   error
#   how
#
sub _default_phrase {
    my ($self) = @_;

    my $how = $self->get('how');

    if ( length $how && $how !~ tr<0-9><>c ) {
        if ( $how == $Cpanel::Socket::Constants::SHUT_RD ) {
            return Cpanel::LocaleString->new(
                'The system failed to shut down a socket’s ability to read because of an error: [_1]',
                $self->get('error'),
            );
        }
        elsif ( $how == $Cpanel::Socket::Constants::SHUT_WR ) {
            return Cpanel::LocaleString->new(
                'The system failed to shut down a socket’s ability to write because of an error: [_1]',
                $self->get('error'),
            );
        }
        elsif ( $how == $Cpanel::Socket::Constants::SHUT_RDWR ) {
            return Cpanel::LocaleString->new(
                'The system failed to shut down a socket fully because of an error: [_1]',
                $self->get('error'),
            );
        }
    }

    die "Invalid “how” parameter: “$how”";
}

1;
