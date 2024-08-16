package Cpanel::Exception::IO::ChmodError;

# cpanel - Cpanel/Exception/IO/ChmodError.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception::IOError );

use Cpanel::LocaleString ();

#Metadata propreties:
#   permissions (octal)
#   path    - optional, can be an arrayref
#   error
sub _default_phrase {
    my ($self) = @_;

    my ( $path, $error, $permissions, $immutable, $append_only ) = @{ $self->{'_metadata'} }{qw(path error permissions immutable append_only)};

    my $print_perms = sprintf( '%04o', $permissions );

    @{ $self->{'_metadata'} }{qw(euid egid)} = ( $>, $) );

    if ( length $path ) {
        $path = [$path] if !ref $path;

        my @args = (
            $path,
            $print_perms,
            @{ $self->{'_metadata'} }{qw(euid egid)},
            $error,
        );

        if ($immutable) {
            return Cpanel::LocaleString->new( 'The system failed to set the permissions on the immutable (+i) file [list_and_quoted,_1] to “[_2]” (as [asis,EUID]: [_3], [asis,EGID]: [_4]) because of the following error: [_5]', @args );
        }
        elsif ($append_only) {
            return Cpanel::LocaleString->new( 'The system failed to set the permissions on the append-only (+a) file [list_and_quoted,_1] to “[_2]” (as [asis,EUID]: [_3], [asis,EGID]: [_4]) because of the following error: [_5]', @args );
        }

        return Cpanel::LocaleString->new( 'The system failed to set the permissions on [list_and_quoted,_1] to “[_2]” (as [asis,EUID]: [_3], [asis,EGID]: [_4]) because of the following error: [_5]', @args );
    }

    my @args = (
        $print_perms,
        @{ $self->{'_metadata'} }{qw(euid egid)},
        $error,
    );

    if ($immutable) {
        return Cpanel::LocaleString->new( 'The system failed to set the permissions on one or more immutable (+i) filesystem nodes to “[_1]” (as [asis,EUID]: [_2], [asis,EGID]: [_3]) because of the following error: [_4]', @args );

    }
    elsif ($append_only) {
        return Cpanel::LocaleString->new( 'The system failed to set the permissions on one or more append-only (+a) inodes to “[_1]” (as [asis,EUID]: [_2], [asis,EGID]: [_3]) because of the following error: [_4]', @args );

    }

    return Cpanel::LocaleString->new( 'The system failed to set the permissions on one or more inodes to “[_1]” (as [asis,EUID]: [_2], [asis,EGID]: [_3]) because of the following error: [_4]', @args );
}

1;
