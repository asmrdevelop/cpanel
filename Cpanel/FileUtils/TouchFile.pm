package Cpanel::FileUtils::TouchFile;

# cpanel - Cpanel/FileUtils/TouchFile.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::FileUtils::TouchFile - Abstraction for creating a touch file

=head1 SYNOPSIS

    use Cpanel::FileUtils::TouchFile;

    #See below before using this!
    Cpanel::FileUtils::TouchFile::touchfile("/touchfile");

=head1 CAVEATS

This module does multiple system calls internally; thus, when it fails there
isn’t a reliable means of knowing what specifically caused the failure.

Instead of using this module, consider L<Cpanel::FileUtils::Touch>.

=cut

use constant {
    _ENOENT => 2,
};

my $logger;

our $VERSION = '1.3';

sub _log {
    my ( $level, $msg ) = @_;

    require Cpanel::Logger;
    $logger ||= Cpanel::Logger->new();
    $logger->$level($msg);

    return;
}

my $mtime;

sub touchfile {
    my ( $file, $verbose, $fail_ok ) = @_;

    if ( !defined $file ) {
        _log( 'warn', "touchfile called with undefined file" );
        return;
    }

    my $mtime;

    # Try utime first
    if ( utime undef, undef, $file ) {
        return 1;
    }
    elsif ( $! != _ENOENT() ) {
        _log( 'warn', "utime($file) as $>: $!" );

        $mtime = -e $file ? ( stat _ )[9] : 0;    # for warnings-safe numeric comparison

        #If stat() failed because of ENOENT, then nothing else we do here
        #will work. We probably shouldn’t be here in the first place, but
        #rather than die() for now let’s just keep status quo behavior with
        #a warn() and return().
        if ( !$mtime && $! != _ENOENT ) {
            _log( 'warn', "Failed to stat($file) as $>: $!" );
            return;
        }
    }

    $mtime = ( stat $file )[9] // 0;

    # if utime does not work try open
    if ( open my $fh, '>>', $file ) {    # append so we don't wipe out contents
        my $mtime_after_open = ( stat $fh )[9] || 0;    # for warnings safe numeric comparison
        return 1 if $mtime != $mtime_after_open;        # in case open does not change it, see comment below
    }
    else {
        _log( 'warn', "Failed to open(>> $file) as $>: $!" ) unless $fail_ok;
    }

    if ($fail_ok) { return; }

    # this may happen if file exists and a mere open won't change it, printing to the
    # filehandle will but it adds to the contents even with '' or undef and/or $/ undef
    # so just to see if our little open() did the trick we fo this if, if not then try other means...
    my $at_this_point = ( stat $file )[9] || 0;    # for warnings safe numeric comparison
    if ( $mtime == $at_this_point ) {

        my $new_at_this_point = ( stat $file )[9] || 0;    # for warnings safe numeric comparison
        if ( $mtime == $new_at_this_point ) {
            if ($verbose) {
                _log( 'info', 'Trying to do system “touch” command!' );
            }
            if ( system( 'touch', $file ) != 0 ) {
                if ($verbose) {
                    _log( 'info', 'system method 1 failed.' );
                }
            }
        }
    }

    if ( !-e $file ) {    # obvisouly it didn't touch it if it doesn't exist...
        _log( 'warn', "Failed to create $file: $!" );
        return;
    }
    else {

        # even the "other means" couldn't do it so:
        my $after_all_that = ( stat $file )[9] || 0;    # for warnings safe numeric comparison
        if ( $mtime && $mtime == $after_all_that ) {
            _log( 'warn', "mtime of “$file” not changed!" );
            return;
        }
        return 1;
    }
}

1;
