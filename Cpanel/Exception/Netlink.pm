package Cpanel::Exception::Netlink;

# cpanel - Cpanel/Exception/Netlink.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Exception::Netlink - errors from L<netlink(7)>

=head1 SYNOPSIS

    die Cpanel::Exception::create('Netlink', [ error => $errno_dualvar, message => $message_that_prompted_error ]);

=head1 DISCUSSION

When Netlink sends a NLMSG_ERROR, the message body includes an errno
value as well as the sent message that prompted the error.

This error class assumes that the caller will convert the errno value into
a dualvar, à la C<$!>.

=cut

use parent qw( Cpanel::Exception::ErrnoBase );

use Cpanel::LocaleString ();

#Named arguments:
#   error
#   message - not shown in string, but potentially useful?
#
sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new(
        'A [asis,Netlink] error occurred: [_1]',
        $self->get('error'),
    );
}

1;
