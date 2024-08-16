package Cpanel::Exception::SystemCall;

# cpanel - Cpanel/Exception/SystemCall.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# NOTE: This is for errors from syscall() &c.
# It is **NOT** for a failure from executing an external command.
#
# Are you wanting ProcessFailed::Error instead?
#----------------------------------------------------------------------

use strict;
use warnings;

use parent qw( Cpanel::Exception::ErrnoBase );

use Cpanel::LocaleString ();

#Named arguments:
#   name
#   error
#
sub _default_phrase {
    my ($self) = @_;

    if ( my $args_ar = $self->get('arguments') ) {
        return Cpanel::LocaleString->new(
            'The system failed to execute the system call “[_1]” ([_2]) because of an error: [_3]',
            $self->get('name'),
            "@$args_ar",
            $self->get('error'),
        );
    }

    return Cpanel::LocaleString->new(
        'The system failed to execute the system call “[_1]” because of an error: [_2]',
        $self->get('name'),
        $self->get('error'),
    );
}

1;
