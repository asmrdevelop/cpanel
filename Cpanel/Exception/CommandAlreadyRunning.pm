package Cpanel::Exception::CommandAlreadyRunning;

# cpanel - Cpanel/Exception/CommandAlreadyRunning.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

#Parameters:
#   pid
sub _default_phrase {
    my ($self) = @_;

    if ( $self->get('file') ) {
        return Cpanel::LocaleString->new(
            'The command already has an active [asis,PIDFile] at “[_1]” and is running with the process [asis,ID]: [_2]',
            $self->get('file'),
            $self->get('pid'),
        );

    }
    else {
        return Cpanel::LocaleString->new(
            'The command is already running with the process [asis,ID]: [_1]',
            $self->get('pid'),
        );
    }
}

#Make these exceptions context-sensitive: they will only print a stack trace
#if this function runs outside an eval {}.
sub _spew {
    my ($self) = @_;

    if ($^S) {
        return $self->SUPER::_spew();
    }

    return $self->get_string_no_id() . "\n";
}

1;
