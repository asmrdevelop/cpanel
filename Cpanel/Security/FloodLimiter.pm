#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - Cpanel/Security/FloodLimiter.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Security::FloodLimiter;

use strict;
use warnings;

use Cpanel::SafeFile ();

=head1 NAME

Cpanel::Security::FloodLimiter

=head2 get_count

=head3 Purpose

    Loads the flood control data.

=head3 Arguments

    $path - string - path to save to.

=head3 Returns

    list with the following positional elements:

        $time - timestamp of last request.
        $count - number of attempts as of the timestamp.

=cut

sub get_count {
    my ($path) = @_;
    my ( $time, $count ) = ( 0, 0 );

    return ( $time, $count ) if !-e $path;

    my $count_fh;
    my $lock = Cpanel::SafeFile::safeopen( $count_fh, '<', $path );    #safesecure
    if ($lock) {
        my $eline = readline($count_fh);
        chomp $eline;
        ( $time, $count ) = split( /=/, $eline, 2 );
        Cpanel::SafeFile::safeclose( $count_fh, $lock );
    }
    else {
        die "Can not acquire lock for flood file at $path with issue: $!.";
    }

    return ( $time, $count );
}

=head2 set_count

=head3 Purpose

    Saves the flood control information.

=head3 Arguments

    $path - string - path to save to.
    $now  - number - updated timestamp.
    $count - number - updated count.

=head3 Returns

    n/a

=cut

sub set_count {
    my ( $path, $now, $count ) = @_;

    my $count_fh;
    my $lock = Cpanel::SafeFile::safeopen( $count_fh, '>', $path );    #safesecure
    if ($lock) {
        print {$count_fh} "$now=$count\n";
        Cpanel::SafeFile::safeclose( $count_fh, $lock );
    }
    else {
        die "Cant acquire lock for flood file at: $path.";
    }
    return;
}

=head2 is_flooding

=head3 Purpose

    Helper to determine if the requests are being flooded
    for the given period.

=head3 Arguments

    hash - containing the following properties:
        path - string - path to the storage file for the monitored request.
        window - number - number of seconds for the retry window. Defaults to 1 hr.
        retries - number - number of retries in the window. Defaults to 3.


=head3 Returns

    boolean - truthy if requests are coming in to fast. falsy otherwise.

=cut

sub is_flooding {
    my (%opts) = @_;

    $opts{window}  = 3600 if !$opts{window};    # 3600 sec => 1 hr
    $opts{retries} = 3    if !$opts{retries};

    die "path parameter missing."                       if !$opts{path};
    die "window parameter must be a positive integer."  if $opts{window}  !~ /^\d+$/ or $opts{window} < 1;
    die "retries parameter must be a positive integer." if $opts{retries} !~ /^\d+$/ or $opts{retries} < 1;

    my ( $time, $count ) = get_count( $opts{path} );
    my $now = _time();

    if ( ( $time + $opts{window} ) < $now ) {
        $count = 0;
    }

    if ( $time > $now ) {
        $time = $now;
    }
    $count++;

    set_count( $opts{path}, $now, $count );
    if (   ( $time + $opts{window} > $now )
        && ( $count > $opts{retries} ) ) {
        return 1;
    }

    return 0;
}

# Mockable call.
sub _time {
    return time();
}

1;
