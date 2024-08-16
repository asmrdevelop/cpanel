package Cpanel::Exception::IO::ExecError;

# cpanel - Cpanel/Exception/IO/ExecError.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# XXX XXX XXX HEY YOU!! XXX XXX XXX
#
# ExecError means that an exec() has failed. It does NOT mean that the
# command executed but then ended prematurely from a signal or error.
#
# If you want to express a premature end of a process that did successfully
# exec(), see the ProcessFailed::* modules.
#----------------------------------------------------------------------

use strict;
use warnings;

use parent qw( Cpanel::Exception::IOError );

use Cpanel::LocaleString ();

#metadata parameters:
#   error
#   path  - optional
#
sub _default_phrase {
    my ($self) = @_;

    die 'Need “error”!' if !$self->get('error');

    if ( $self->get('path') ) {
        return Cpanel::LocaleString->new(
            'The system failed to execute the program “[_1]” because of an error: [_2]',
            $self->get('path'),
            $self->get('error'),
        );
    }

    return Cpanel::LocaleString->new(
        'The system failed to execute an unknown program because of an error: [_1]',
        $self->get('error'),
    );
}

1;
