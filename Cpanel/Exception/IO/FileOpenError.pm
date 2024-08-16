package Cpanel::Exception::IO::FileOpenError;

# cpanel - Cpanel/Exception/IO/FileOpenError.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception::IOError );

use Cpanel::LocaleString ();

#Metadata propreties:
#   mode (OPTIONAL, same as mode passed to 3-arg open() OR sysopen())
#   permissions (OPTIONAL, same as passed to Cpanel::SafeFile::safesysopen())
#   path
#   error
sub _default_phrase {
    my ($self) = @_;

    my ( $mode, $immutable, $append_only ) = @{ $self->{'_metadata'} }{qw(mode immutable append_only)};

    if ( length($mode) && ( $mode =~ m<\A[0-9]+]\z> ) ) {
        return $self->_default_phrase_for_sysopen();    ## no extract maketext
    }

    my $for_reading = $mode && ( $mode =~ tr{<+}{} );
    my $for_writing = $mode && ( $mode =~ tr{>+}{} );

    my @args = @{ $self->{'_metadata'} }{qw(path error)};

    if ($for_reading) {
        if ($for_writing) {
            if ($immutable) {
                return Cpanel::LocaleString->new( 'The system failed to open the immutable (+i) file “[_1]” for reading and writing because of an error: [_2]', @args );
            }
            elsif ($append_only) {
                return Cpanel::LocaleString->new( 'The system failed to open the append-only (+a) file “[_1]” for reading and writing because of an error: [_2]', @args );
            }
            else {
                return Cpanel::LocaleString->new( 'The system failed to open the file “[_1]” for reading and writing because of an error: [_2]', @args );
            }
        }
        elsif ($immutable) {
            return Cpanel::LocaleString->new( 'The system failed to open the immutable (+i) file “[_1]” for reading because of an error: [_2]', @args );
        }
        elsif ($append_only) {
            return Cpanel::LocaleString->new( 'The system failed to open the append-only (+a) file “[_1]” for reading because of an error: [_2]', @args );
        }

        return Cpanel::LocaleString->new( 'The system failed to open the file “[_1]” for reading because of an error: [_2]', @args );
    }
    elsif ($for_writing) {
        if ($immutable) {
            return Cpanel::LocaleString->new( 'The system failed to open the immutable (+i) file “[_1]” for writing because of an error: [_2]', @args );
        }
        elsif ($append_only) {
            return Cpanel::LocaleString->new( 'The system failed to open the append-only (+a) file “[_1]” for writing because of an error: [_2]', @args );
        }

        return Cpanel::LocaleString->new( 'The system failed to open the file “[_1]” for writing because of an error: [_2]', @args );
    }
    elsif ($immutable) {
        return Cpanel::LocaleString->new( 'The system failed to open the immutable (+i) file “[_1]” because of an error: [_2]', @args );
    }
    elsif ($append_only) {
        return Cpanel::LocaleString->new( 'The system failed to open the append-only (+a) file “[_1]” because of an error: [_2]', @args );
    }

    return Cpanel::LocaleString->new( 'The system failed to open the file “[_1]” because of an error: [_2]', @args );
}

sub _default_phrase_for_sysopen {
    my ($self) = @_;

    my ( $path, $error, $mode, $permissions, $immutable, $append_only ) = @{ $self->{'_metadata'} }{qw(path error mode permissions immutable append_only)};

    my @flags;
    while ( my ( $key, $val ) = each %Cpanel::Fcntl::Constants:: ) {
        next if substr( $key, 0, 2 ) ne 'O_';
        next if ref $val ne 'SCALAR';

        push @flags, $key if $mode & $$val;
    }

    if ( length($permissions) ) {
        my $octal_permissions = sprintf( '%04o', $permissions );

        my @args = (
            $path,
            $octal_permissions,
            [ sort @flags ],
            $error,
        );

        if ($immutable) {
            return Cpanel::LocaleString->new( 'The system failed to open the immutable (+i) file “[_1]” with permissions “[_2]” and flags [list_and_quoted,_3] because of an error: [_4]', @args );
        }
        elsif ($append_only) {
            return Cpanel::LocaleString->new( 'The system failed to open the append-only (+a) file “[_1]” with permissions “[_2]” and flags [list_and_quoted,_3] because of an error: [_4]', @args );
        }

        return Cpanel::LocaleString->new( 'The system failed to open the file “[_1]” with permissions “[_2]” and flags [list_and_quoted,_3] because of an error: [_4]', @args );
    }

    my @args = (
        $path,
        [ sort @flags ],
        $error,
    );

    if ($immutable) {
        return Cpanel::LocaleString->new( 'The system failed to open the immutable (+i) file “[_1]” with flags [list_and_quoted,_2] because of an error: [_3]', @args );
    }
    elsif ($append_only) {
        return Cpanel::LocaleString->new( 'The system failed to open the append-only (+a) file “[_1]” with flags [list_and_quoted,_2] because of an error: [_3]', @args );
    }

    return Cpanel::LocaleString->new( 'The system failed to open the file “[_1]” with flags [list_and_quoted,_2] because of an error: [_3]', @args );
}

1;
