package Cpanel::Exception::IO::FileLockError;

# cpanel - Cpanel/Exception/IO/FileLockError.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception::IOError );

use Cpanel::LocaleString ();

=encoding utf-8

=head1 NAME

Cpanel::Exception::IO::FileLockError

=head1 DESCRIPTION

An exception for when a file cannot be locked.

=head1 SYNOPSIS

    die Cpanel::Exception::create(
        'IO::FileLockError',
        [ 'path' => '/etc/mailips', 'error' => $! ]
    );

    my $attributes = Cpanel::FileUtils::Attr::get_file_or_fh_attributes( $opts{'path'} );

    if ($lock_err) {
         die Cpanel::Exception::create(
        'IO::FileLockError',
          [
            'path' => $opts{'path'},
            'error' => $lock_err,
            'immutable' => $attributes->{'IMMUTABLE'},
            'append_only' => $attributes->{'APPEND_ONLY'}
          ]
        );
    }

=cut

#Required Metadata props:
#   path    - the file path that was going to be locked
#   error   - the error
#Optional Metadata props:
#   immutable - If the file being locked was immutable
#   append_only - If the file being locked was append_only
sub _default_phrase {
    my ($self) = @_;

    my ( $path, $error, $immutable, $append_only ) = @{ $self->{'_metadata'} }{qw(path error immutable append_only)};

    my @args = (
        $path,
        $>,    # euid
        $),    # egid
        $error,
    );

    if ($immutable) {
        return Cpanel::LocaleString->new( 'The system failed to lock the immutable (+i) file “[_1]” (as [asis,EUID]: [_2], [asis,EGID]: [_3]) because of the following error: [_4]', @args );
    }
    elsif ($append_only) {
        return Cpanel::LocaleString->new( 'The system failed to lock the append-only (+a) file “[_1]” (as [asis,EUID]: [_2], [asis,EGID]: [_3]) because of the following error: [_4]', @args );
    }

    return Cpanel::LocaleString->new( 'The system failed to lock the file “[_1]” (as [asis,EUID]: [_2], [asis,EGID]: [_3]) because of the following error: [_4]', @args );
}

1;
