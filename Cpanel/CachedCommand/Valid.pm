package Cpanel::CachedCommand::Valid;

# cpanel - Cpanel/CachedCommand/Valid.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Cpanel::StatCache ();
use Cpanel::Debug     ();

=head1 NAME

Cpanel::CachedCommand::Valid

=head1 SYNOPSIS

Check to see if a cPanel datastore cache file is valid

  my $valid = Cpanel::CachedCommand::Valid::is_cache_valid(
            'binary'               => $binary,
            'datastore_file'       => $datastore_file,
            'datastore_file_mtime' => $datastore_file_mtime,
            'ttl'                  => $ttl,
            'mtime'                => $mtime,
            'min_expire_time'      => $min_expire_time,
        );


=head1 DESCRIPTION

This module provides functionality to check the validity of the
caches uses by Cpanel::CachedCommand

=head1 METHODS

=head2 is_cache_valid

Check the validity of a Cpanel::CachedCommand/datastore cache.

=head3 Arguments

A hash with the following keys:

  datastore_file       - The key that references the corresponding file in the datastore cache directory
  datastore_file_mtime - The mtime of the file in the datastore cache directory
  datastore_file_size  - The size of the file datastore cache directory
  binary               - A binary to check the mtime of that can bust the cache
  ttl                  - The maximum amount of time the cache should live for
  min_expire_time      - The maximum amount of time the cache should live for (same as ttl under another name)
  mtime                - If the cache is older then mtime it will be marked invalid
  now                  - The current time (can be used to simulate another time)

=head3 Return Value

  0 - The cache is no longer valid
  1 - The cache is still valid

=cut

sub is_cache_valid {    ## no critic qw(Subroutines::ProhibitExcessComplexity) -- needs to be refactored
    my %OPTS = @_;
    my ( $datastore_file, $datastore_file_mtime, $datastore_file_size, $binary, $ttl, $mtime, $min_expire_time, $now ) = ( ( $OPTS{'datastore_file'} || '' ), ( $OPTS{'datastore_file_mtime'} || 0 ), ( $OPTS{'datastore_file_size'} || 0 ), ( $OPTS{'binary'} || '' ), ( $OPTS{'ttl'} || 0 ), ( $OPTS{'mtime'} || 0 ), ( $OPTS{'min_expire_time'} || 0 ), ( $OPTS{'now'} || 0 ) );

    if ( !$datastore_file_mtime && !-e $datastore_file ) {
        print STDERR "is_cache_valid: rejecting $datastore_file because it does not exist.\n" if $Cpanel::Debug::level;
        return 0;
    }

    if ( !$datastore_file_size || !$datastore_file_mtime ) {
        ( $datastore_file_size, $datastore_file_mtime ) = ( stat(_) )[ 7, 9 ];
    }

    if ( $datastore_file_mtime <= 0 ) {
        print STDERR "is_cache_valid: rejecting $datastore_file as mtime is zero.\n" if $Cpanel::Debug::level;
        return 0;
    }

    if ($binary) {
        if ( substr( $binary, 0, 1 ) ne '/' ) {
            require Cpanel::FindBin;
            $binary = Cpanel::FindBin::findbin( $binary, split( /:/, $ENV{'PATH'} ) );
        }
        my ( $binary_mtime, $binary_ctime ) = Cpanel::StatCache::cachedmtime_ctime($binary);
        if ( ( $binary_mtime && $binary_mtime > $datastore_file_mtime ) || ( $binary_ctime && $binary_ctime > $datastore_file_mtime ) ) {
            if ($Cpanel::Debug::level) {
                print STDERR "is_cache_valid: rejecting $datastore_file as binary ($binary) ctime or mtime is newer.\n";
                print STDERR "is_cache_valid: datastore_file:$datastore_file mtime[$datastore_file_mtime]\n";
                print STDERR "is_cache_valid: binary_file:$binary mtime[$binary_mtime] ctime[$binary_ctime]\n";
            }
            return 0;
        }
    }
    $now ||= time();
    if ( $datastore_file_mtime > $now ) {
        print STDERR "is_cache_valid: rejecting $datastore_file as it is from the future (time warp safety).\n" if $Cpanel::Debug::level;
        return 0;
    }
    elsif ( $min_expire_time && $datastore_file_mtime > ( $now - $min_expire_time ) ) {
        print STDERR "is_cache_valid: accept $datastore_file (mtime=$datastore_file_mtime) as min_expire_time ($now - $min_expire_time) is older.\n" if $Cpanel::Debug::level;
        return 1;
    }
    elsif ( $mtime > $datastore_file_mtime ) {
        print STDERR "is_cache_valid: rejecting $datastore_file because mtime ($mtime) is newer then datastore mtime ($datastore_file_mtime).\n" if $Cpanel::Debug::level;
        return 0;
    }
    elsif ( $ttl && ( $datastore_file_mtime + $ttl ) < $now ) {
        print STDERR "is_cache_valid: rejecting $datastore_file as it has reached its time to live.\n" if $Cpanel::Debug::level;
        return 0;
    }

    print STDERR "is_cache_valid: accepting $datastore_file as it passes all tests.\n" if $Cpanel::Debug::level;

    return 1;
}
1;
