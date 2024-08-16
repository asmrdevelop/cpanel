package Cpanel::Exception::RollbackError;

# cpanel - Cpanel/Exception/RollbackError.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::Exception    ();
use Cpanel::LocaleString ();

#Parameters:
#   label (optional) - a name for what failed to roll back
#   error - the error that tells what exactly failed
sub _default_phrase {
    my ($self) = @_;

    my $error_str = Cpanel::Exception::get_string( $self->get('error') );

    if ( $self->get('label') ) {
        return Cpanel::LocaleString->new(
            'The rollback operation “[_1]” failed because of an error: [_2]',
            $self->get('label'),
            $error_str,
        );
    }

    return Cpanel::LocaleString->new(
        'A rollback operation failed because of an error: [_1]',
        $error_str,
    );
}

1;
