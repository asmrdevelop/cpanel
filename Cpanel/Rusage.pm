package Cpanel::Rusage;

# cpanel - Cpanel/Rusage.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=encoding utf-8

=head1 NAME

Cpanel::Rusage - Linux’s C<getrusage> system call.

=head1 SYNOPSIS

    use Cpanel::Rusage ();

    my $usage_hr = Cpanel::Rusage::get_self();

=cut

use strict;
use warnings;

use Cpanel::Exception ();
use Cpanel::Pack      ();

use constant {
    _NR_getrusage => 98,

    _RUSAGE_SELF     => 0,
    _RUSAGE_CHILDREN => -1,

    #This isn’t documented …
    _RUSAGE_BOTH => -2,

    _TEMPLATE_AR => [
        utime_sec  => 'L!',
        utime_msec => 'L!',
        stime_sec  => 'L!',
        stime_msec => 'L!',
        maxrss     => 'L!',
        ixrss      => 'L!',
        idrss      => 'L!',
        isrss      => 'L!',
        minflt     => 'L!',
        majflt     => 'L!',
        nswap      => 'L!',
        inblock    => 'L!',
        oublock    => 'L!',
        msgsnd     => 'L!',
        msgrcv     => 'L!',
        nsignals   => 'L!',
        nvcsw      => 'L!',
        nivcsw     => 'L!',
    ],
};

my $PACKER;

=head1 FUNCTIONS

=head2 $usage_hr = get_self()

Returns information on the present process, exclusive of child
process. See C<RUSAGE_SELF> in C<man 2 getrusage>.

The return is a hash reference with the following members; see
C<man 2 getrusage> for documentation on what these mean:

=over

=item * C<utime_sec>, C<utime_msec> (milliseconds)

=item * C<stime_sec>, C<stime_msec> (milliseconds)

=item * C<maxrss>

=item * C<minflt>, C<majflt>

=item * C<inblock>, C<oublock>

=item * C<nvcsw>, C<nivcsw>

=item * The following are present but unused as of CentOS 7: C<ixrss>,
C<idrss>, C<isrss>, C<nswap>, C<msgsnd>, C<msgrcv>, C<nsignals>

=back

=cut

sub get_self { return _get('SELF') }

=head2 $usage_hr = get_children()

Same as C<get_self()> but for child processes of the current process.
See C<RUSAGE_CHILDREN> in C<man 2 getrusage>.

=cut

sub get_children { return _get('CHILDREN') }

sub _get {
    my ($what) = @_;

    my $who = __PACKAGE__->can("_RUSAGE_$what")->();

    my $PACKER = Cpanel::Pack->new( _TEMPLATE_AR() );

    my $buf = "\0" x $PACKER->sizeof();

    local $!;
    if ( -1 == syscall( 0 + _NR_getrusage(), 0 + $who, $buf ) ) {
        die Cpanel::Exception::create( 'SystemCall', [ name => 'getrusage', error => $! ] );
    }

    return $PACKER->unpack_to_hashref($buf);
}

1;
