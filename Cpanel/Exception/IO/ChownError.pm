package Cpanel::Exception::IO::ChownError;

# cpanel - Cpanel/Exception/IO/ChownError.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception::IOError );

use Cpanel::LocaleString ();

#Metadata propreties:
#   uid
#   gid
#   path    - can be an arrayref
#   error
sub _default_phrase {
    my ($self) = @_;

    my ( $uid, $gid, $path, $error, $immutable, $append_only ) = @{ $self->{'_metadata'} }{qw(uid gid path error immutable append_only)};

    $path = [$path] if length($path) && !ref $path;

    if ( $uid == -1 ) {

        #Should never happen, but ...
        die "Huh? UID and GID were both -1 .. ?" if $gid == -1;

        if ($path) {
            my @args = (
                $gid,
                $path,
                $error,
            );

            if ($immutable) {
                return Cpanel::LocaleString->new( 'The system failed to set the group ID to “[_1]” on the immutable (+i) file [list_and_quoted,_2] because of an error: [_3]', @args );
            }
            elsif ($append_only) {
                return Cpanel::LocaleString->new( 'The system failed to set the group ID to “[_1]” on the append-only (+a) file [list_and_quoted,_2] because of an error: [_3]', @args );
            }

            return Cpanel::LocaleString->new( 'The system failed to set the group ID to “[_1]” on [list_and_quoted,_2] because of an error: [_3]', @args );
        }

        my @args = (
            $gid,
            $error,
        );

        if ($immutable) {
            return Cpanel::LocaleString->new( 'The system failed to set the group ID to “[_1]” on one or more immutable (+i) filesystem nodes because of an error: [_2]', @args );
        }
        elsif ($append_only) {
            return Cpanel::LocaleString->new( 'The system failed to set the group ID to “[_1]” on one or more append-only (+a) filesystem nodes because of an error: [_2]', @args );
        }

        return Cpanel::LocaleString->new( 'The system failed to set the group ID to “[_1]” on one or more filesystem nodes because of an error: [_2]', @args );
    }

    if ( $gid == -1 ) {

        if ($path) {
            my @args = (
                $uid,
                $path,
                $error,
            );

            if ($immutable) {
                return Cpanel::LocaleString->new( 'The system failed to set the user ID to “[_1]” on the immutable (+i) file [list_and_quoted,_2] because of an error: [_3]', @args );

            }
            elsif ($append_only) {
                return Cpanel::LocaleString->new( 'The system failed to set the user ID to “[_1]” on the append-only (+a) file [list_and_quoted,_2] because of an error: [_3]', @args );

            }

            return Cpanel::LocaleString->new( 'The system failed to set the user ID to “[_1]” on [list_and_quoted,_2] because of an error: [_3]', @args );
        }

        my @args = (
            $uid,
            $error,
        );

        if ($immutable) {
            return Cpanel::LocaleString->new( 'The system failed to set the user ID to “[_1]” on one or more immutable (+i) filesystem nodes because of an error: [_2]', @args );
        }
        elsif ($append_only) {
            return Cpanel::LocaleString->new( 'The system failed to set the user ID to “[_1]” on one or more append-only (+a) filesystem nodes because of an error: [_2]', @args );

        }

        return Cpanel::LocaleString->new( 'The system failed to set the user ID to “[_1]” on one or more filesystem nodes because of an error: [_2]', @args );
    }

    if ($path) {
        my @args = (
            $uid,
            $gid,
            $path,
            $error,
        );

        if ($immutable) {
            return Cpanel::LocaleString->new( 'The system failed to set the user ID to “[_1]” and the group ID to “[_2]” on the immutable (+i) file [list_and_quoted,_3] because of an error: [_4]', @args );

        }
        elsif ($append_only) {
            return Cpanel::LocaleString->new( 'The system failed to set the user ID to “[_1]” and the group ID to “[_2]” on the append-only (+a) file [list_and_quoted,_3] because of an error: [_4]', @args );

        }

        return Cpanel::LocaleString->new( 'The system failed to set the user ID to “[_1]” and the group ID to “[_2]” on [list_and_quoted,_3] because of an error: [_4]', @args );
    }

    my @args = (
        $uid,
        $gid,
        $error,
    );

    if ($immutable) {
        return Cpanel::LocaleString->new( 'The system failed to set the user ID to “[_1]” and the group ID to “[_2]” on one or more immutable (+i) filesystem nodes because of an error: [_3]', @args );
    }
    elsif ($append_only) {
        return Cpanel::LocaleString->new( 'The system failed to set the user ID to “[_1]” and the group ID to “[_2]” on one or more append-only (+a) filesystem nodes because of an error: [_3]', @args );

    }

    return Cpanel::LocaleString->new( 'The system failed to set the user ID to “[_1]” and the group ID to “[_2]” on one or more filesystem nodes because of an error: [_3]', @args );
}

1;
