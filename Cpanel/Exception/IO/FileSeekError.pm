package Cpanel::Exception::IO::FileSeekError;

# cpanel - Cpanel/Exception/IO/FileSeekError.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception::IOError );

use Cpanel::Fcntl::Constants ();
use Cpanel::LocaleString     ();

#Parameters:
#   path
#   position
#   whence
#   error
sub _default_phrase {
    my ($self) = @_;

    my ( $path, $position, $whence, $error ) = @{ $self->{'_metadata'} }{qw( path position whence error )};

    my $path_is_a_path_not_a_filehandle = length $path && !ref $path;

    if ( $whence == $Cpanel::Fcntl::Constants::SEEK_SET ) {
        if ($position) {
            if ($path_is_a_path_not_a_filehandle) {
                return Cpanel::LocaleString->new( 'The system failed to move the pointer for the file “[_1]” to [quant,_2,byte,bytes] after the beginning because of an error: [_3]', $path, $position, $error );
            }
            else {
                return Cpanel::LocaleString->new( 'The system failed to move the pointer for a file to [quant,_1,byte,bytes] after the beginning because of an error: [_2]', $position, $error );
            }
        }
        elsif ($path_is_a_path_not_a_filehandle) {
            return Cpanel::LocaleString->new(
                'The system failed to move the pointer for the file “[_1]” to the beginning because of an error: [_2]',
                $path,
                $error,
            );
        }

        return Cpanel::LocaleString->new(
            'The system failed to move the pointer for a file to the beginning because of an error: [_1]',
            $error,
        );
    }
    elsif ( $whence == $Cpanel::Fcntl::Constants::SEEK_CUR ) {
        if ( $position >= 0 ) {
            if ($path_is_a_path_not_a_filehandle) {
                return Cpanel::LocaleString->new( 'The system failed to advance the pointer for the file “[_1]” by [quant,_2,byte,bytes] because of an error: [_3]', $path, $position, $error );
            }
            else {
                return Cpanel::LocaleString->new( 'The system failed to advance the pointer for a file by [quant,_1,byte,bytes] because of an error: [_2]', $position, $error );
            }
        }
        elsif ($path_is_a_path_not_a_filehandle) {
            return Cpanel::LocaleString->new( 'The system failed to move the pointer for the file “[_1]” back by [quant,_2,byte,bytes] because of an error: [_3]', $path, -$position, $error );
        }

        return Cpanel::LocaleString->new( 'The system failed to move the pointer for a file back by [quant,_1,byte,bytes] because of an error: [_2]', -$position, $error );
    }
    elsif ( $whence == $Cpanel::Fcntl::Constants::SEEK_END ) {
        if ($position) {
            if ($path_is_a_path_not_a_filehandle) {
                return Cpanel::LocaleString->new( 'The system failed to move the pointer for the file “[_1]” to [quant,_2,byte,bytes] before the end because of an error: [_3]', $path, -$position, $error );
            }
            else {
                return Cpanel::LocaleString->new( 'The system failed to move the pointer for a file to [quant,_1,byte,bytes] before the end because of an error: [_2]', -$position, $error );
            }
        }
        elsif ($path_is_a_path_not_a_filehandle) {
            return Cpanel::LocaleString->new(
                'The system failed to move the pointer for the file “[_1]” to the end because of an error: [_2]',
                $path,
                $error,
            );
        }

        return Cpanel::LocaleString->new(
            'The system failed to move the pointer for a file to the end because of an error: [_1]',
            $error,
        );
    }

    return Cpanel::LocaleString->new(
        'The arguments to [asis,seek()] (“[_1]”, “[_2]”, “[_3]”) are invalid: [_4]',
        $path,
        $position,
        $whence,
        $error,
    );
}

1;
