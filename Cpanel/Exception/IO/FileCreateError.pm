package Cpanel::Exception::IO::FileCreateError;

# cpanel - Cpanel/Exception/IO/FileCreateError.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception::IOError );

use Cpanel::LocaleString ();

#Parameters:
#   path
#   error
#   permissions (optional)
sub _default_phrase {
    my ($self) = @_;

    @{ $self->{'_metadata'} }{qw(euid egid)} = ( $>, $) );

    if ( defined $self->{'_metadata'}{'permissions'} ) {
        my $octal_permissions = sprintf( '%04o', $self->{'_metadata'}{'permissions'} );
        return Cpanel::LocaleString->new(
            'The system failed to create the file “[_1]” with permissions “[_2]” (as [asis,EUID]: [_3], [asis,EGID]: [_4]) because of the following error: [_5]',
            $self->{'_metadata'}{'path'},
            $octal_permissions,
            @{ $self->{'_metadata'} }{qw(euid egid error)},
        );
    }

    return Cpanel::LocaleString->new(
        'The system failed to create the file “[_1]” (as [asis,EUID]: [_2], [asis,EGID]: [_3]) because of the following error: [_4]',
        @{ $self->{'_metadata'} }{qw( path euid egid error )},
    );
}

1;
