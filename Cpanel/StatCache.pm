package Cpanel::StatCache;

# cpanel - Cpanel/StatCache.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our $VERSION = 0.4;

# Hash of file names with an array ref
# [ 0 = mtime, 1 = size, 2 = ctime ]
my %STATCACHE;

=head1 NAME

Cpanel::StatCache - In-memory cache of stat() results

=head1 DESCRIPTION

Caches the results of stat() calls so that repeated lookups on the same file over a
short period of time do not cause repeated filesystem access.

=head1 CONFIGURATION (optional)

=head2 Use lstat()

If you are dealing with a symlink (or something that might sometimes be a symlink)
and want to look up the attributes of the symlink itself rather than the target, you
can temporarily adjust the behavior of Cpanel::StatCache by setting the following
boolean:

  local $Cpanel::StatCache::USE_LSTAT = 1;

=cut

our $USE_LSTAT = 0;

sub StatCache_init { }

=head1 FUNCTIONS

=head2 cachedmtime(PATH)

Returns the modification time of the file at PATH.

=cut

sub cachedmtime {
    return (
        exists $STATCACHE{ $_[0] } ? $STATCACHE{ $_[0] }->[0]
        : (
            $STATCACHE{ $_[0] } = (
                  $USE_LSTAT && -l $_[0] ? [ ( lstat(_) )[ 9, 7, 10 ] ]
                : -e $_[0]               ? [ ( stat(_) )[ 9, 7, 10 ] ]
                :                          [ 0, 0, 0 ]
            )
        )->[0]
    );
}

=head2 cachedmtime_size(PATH)

Returns the modification time and size of the file at PATH.

=cut

# returns the mtime,size of the file
sub cachedmtime_size {
    return (
        exists $STATCACHE{ $_[0] } ? @{ $STATCACHE{ $_[0] } }[ 0, 1 ]
        : @{
            (
                $STATCACHE{ $_[0] } = (
                      $USE_LSTAT && -l $_[0] ? [ ( lstat(_) )[ 9, 7, 10 ] ]
                    : -e $_[0]               ? [ ( stat(_) )[ 9, 7, 10 ] ]
                    :                          [ 0, 0, 0 ]
                )
            )
        }[ 0, 1 ]
    );
}

=head2 cachedmtime_ctime(PATH)

Returns the modification time and creation time of the file at PATH.

=cut

sub cachedmtime_ctime {
    return (
        exists $STATCACHE{ $_[0] } ? @{ $STATCACHE{ $_[0] } }[ 0, 2 ]
        : @{
            (
                $STATCACHE{ $_[0] } = (
                      $USE_LSTAT && -l $_[0] ? [ ( lstat(_) )[ 9, 7, 10 ] ]
                    : -e $_[0]               ? [ ( stat(_) )[ 9, 7, 10 ] ]
                    :                          [ 0, 0, 0 ]
                )
            )
        }[ 0, 2 ]
    );
}

=head2 clearcache()

Clears the in-memory cache.

=cut

sub clearcache {
    %STATCACHE = ();
    return 1;
}

1;
