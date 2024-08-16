package Cpanel::Exception::AdminBinError;

# cpanel - Cpanel/Exception/AdminBinError.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# NOTE: This error class is for failures in the admin bin module itself,
# *not* exceptions that the script sends back and we need to recreate
# as the user.
#----------------------------------------------------------------------

use strict;
use warnings;

use parent qw(
  Cpanel::Exception
  Cpanel::ChildErrorStringifier
);

use Cpanel::LocaleString ();

#Params:
#   CHILD_ERROR
#   message_from_subprocess
sub _default_phrase {
    my ($self) = @_;

    if ( $self->signal_code() ) {
        if ( length $self->{'_metadata'}{'message_from_subprocess'} ) {
            return Cpanel::LocaleString->new(
                'The administrative request ended prematurely because it received the “[_1]” ([_2]) signal. It gave the following output: [_3]',
                $self->signal_name(),
                $self->signal_code(),
                $self->{'_metadata'}{'message_from_subprocess'},
            );
        }
        else {
            return Cpanel::LocaleString->new(
                'The administrative request ended prematurely because it received the “[_1]” ([_2]) signal.',
                $self->signal_name(),
                $self->signal_code(),
            );
        }
    }

    if ( $self->error_code() ) {
        my $err_display = ( $self->error_name() ? $self->error_name() . '/' : q<> ) . $self->error_code();

        if ( length $self->{'_metadata'}{'message_from_subprocess'} ) {
            return Cpanel::LocaleString->new(
                'The administrative request failed because of an error ([_1]) with output: [_2]',
                $err_display,
                $self->{'_metadata'}{'message_from_subprocess'},
            );
        }
        else {
            return Cpanel::LocaleString->new(
                'The administrative request failed because of an error ([_1]).',
                $err_display,
            );
        }
    }
}

sub CHILD_ERROR {
    my ($self) = @_;

    return $self->{'_metadata'}{'CHILD_ERROR'};
}

1;
