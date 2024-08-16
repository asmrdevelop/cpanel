package Cpanel::TimeHiRes;

# cpanel - Cpanel/TimeHiRes.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::TimeHiRes - replacement for core L<Time::HiRes>

=head1 SYNOPSIS

    #Precise to nanoseconds
    my $time = Cpanel::TimeHiRes::time();
    ($secs, $nsecs) = Cpanel::TimeHiRes::clock_gettime();

    Cpanel::TimeHiRes::sleep(2.555);

    #Precise only to microseconds
    ($secs, $usecs) = Cpanel::TimeHiRes::gettimeofday();

=cut

use constant {
    _gettimeofday => 96,

    _clock_gettime  => 228,
    _CLOCK_REALTIME => 0,

    _EINTR => 4,

    _PACK_TEMPLATE => 'L!L!',
};

=head1 FUNCTIONS

=head2 ($secs, $nsecs) = clock_gettime()

Returns the current time as discrete second and nanosecond values.

=cut

sub clock_gettime {
    my $timeval = pack( _PACK_TEMPLATE, () );

    _get_time_from_syscall(
        _clock_gettime,
        _CLOCK_REALTIME,
        $timeval,
    );

    return unpack( _PACK_TEMPLATE, $timeval );
}

=head2 time()

Like C<clock_gettime()> except it returns the time as a
single (floating-point) value. Like L<Time::HiRes>’s function of the
same name, it can work as a drop-in replacement for Perl’s built-in
as long as the calling code doesn’t depend on an integer return.

=cut

sub time {
    my ( $secs, $nsecs ) = clock_gettime();

    return $secs + ( $nsecs / 1_000_000_000 );
}

=head2 sleep(WAIT_TIME)

A drop-in replacement for Perl’s built-in. WAIT_TIME can include
fractions of a second, e.g, C<2.5>.

=cut

sub sleep {
    my ($secs) = @_;

    #NB: select() only gives precision to microseconds;
    #we could switch to pselect() and get nanosecond-level precision,
    #but what would be the benefit?

    local $!;
    my $retval = select( undef, undef, undef, $secs );
    if ( $retval == -1 && $! != _EINTR ) {
        require Cpanel::Exception;
        die 'Cpanel::Exception'->can('create')->( 'SystemCall', 'The system failed to suspend command execution for [quant,_1,second,seconds] because of an error: [_2]', [ $secs, $! ] );
    }

    return $secs;
}

=head2 ($secs, $usecs) = gettimeofday()

Like C<clock_gettime()> but returns microseconds instead of nanoseconds.
There’s probably no reason to call this in new code unless for some reason
you want less precision than C<clock_gettime()> gives.

=cut

sub gettimeofday {
    my $timeval = pack( _PACK_TEMPLATE, () );

    _get_time_from_syscall(
        _gettimeofday,
        $timeval,
        undef,
    );

    return unpack( _PACK_TEMPLATE, $timeval );
}

#----------------------------------------------------------------------

sub _get_time_from_syscall {    ##no critic qw(RequireArgUnpacking)
    my $syscall_num = shift;

    # Template must be L!L! to support 64bit
    local $!;
    my $retval = syscall( $syscall_num, @_ );
    if ( $retval == -1 ) {
        require Cpanel::Exception;
        die 'Cpanel::Exception'->can('create')->( 'SystemCall', 'The system failed to retrieve the time because of an error: [_1]', [$!] );
    }

    return;
}

1;
