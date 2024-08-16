package Cpanel::Inotify;

# cpanel - Cpanel/Inotify.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Inotify - Inotify support for Perl

=head1 SYNOPSIS

    my $infy = Cpanel::Inotify->new( flags => [ 'NONBLOCK', … ] );

    my $descr = $infy->add(
        '/filesystem/path',
        flags => [ 'ACCESS', 'MODIFY', … ]
    );

    my @events = $infy->poll();

=head1 DESCRIPTION

This wraps system calls into Linux’s inotify feature. For more information
about inotify, run C<man 7 inotify>.

=head1 CAVEAT EMPTOR

The kernel’s Inotify logic doesn’t seem to appreciate having multiple
listeners for the same path on the same Inotify instance. This doesn’t
seem to be documented. (The C<MASK_ADD> flag might help with this?)

=head1 DESIGN

It is by intent that the underlying Inotify file handle is not exposed
to the caller. If it’s desired at some point to get/set attributes on that
file handle, please implement methods on this class specifically for that
purpose rather than exposing the file handle.

This module is meant to be as “bare-bones” as possible—just a shim around
the system calls.

=head1 METHODS

=cut

use strict;
use warnings;

use Cpanel::Autodie          ();
use Cpanel::Context          ();
use Cpanel::Exception        ();
use Cpanel::Fcntl::Constants ();
use Cpanel::Pack             ();
use Cpanel::Syscall          ();

use constant POLL_SIZE => 65536;

use constant READ_TEMPLATE => (
    wd     => 'i',    #int        Watch descriptor
    mask   => 'I',    #uint32_t   Mask of events
    cookie => 'I',    #uint32_t   Unique cookie associating related events
                      #           (for rename(2))
    len    => 'I',    #uint32_t   Size of “name” field
                      #name    Z* #char[]     Optional null-terminated name
);

my %add_flags;
my %read_flags;
my %init1_flag;

my $UNPACK_OBJ;
my $UNPACK_SIZE;

=head2 I<CLASS>->new( KEY1 => VALUE1, … )

This creates an Inotify instance. The only accepted key right now is
C<flags>, which must be an array reference that contains the flags to pass
to the underlying C<inotify_init1> system call. These flags are passed as
strings, minus their C analogues’ initial C<IN_> prefix.

As of when this module was written, the only allowed flags are
C<NONBLOCK> and C<CLOEXEC>.

=cut

sub new {
    my ( $class, %opts ) = @_;

    if ( !$UNPACK_OBJ ) {
        $UNPACK_OBJ  = Cpanel::Pack->new( [ READ_TEMPLATE() ] );
        $UNPACK_SIZE = $UNPACK_OBJ->sizeof();

        _setup_flags();
    }

    my @given_flags = $opts{'flags'} ? @{ $opts{'flags'} } : ();

    my $mask = 0;
    for my $f (@given_flags) {
        $mask |= $init1_flag{$f} || do {
            die Cpanel::Exception->create_raw("Invalid inotify_init1 flag: “$f”");
        };
    }

    my $fd = Cpanel::Syscall::syscall( 'inotify_init1', $mask );

    my %self = (
        _fd => $fd,
    );
    Cpanel::Autodie::open( $self{'_fh'}, '<&=', $fd );

    return bless \%self, $class;
}

=head2 $descr = I<OBJ>->add( PATH, KEY1 => VALUE1, … )

This adds a path to an Inotify instance. See C<man 2 inotify_add_watch> for
more details about all this can do. The return is a number that Inotify
assigns to refer to this specific watch and that will correlate with the
results of a call to C<poll()>.

The only accepted key is C<flags>, which gives the flags to pass to the
underlying C<inotify_add_watch> system call in string form.

B<NOTE>: Flags for this call have the initial C<IN_> removed for conciseness:
so, where in C you’d give C<IN_MOVE>, here it’s just C<MOVE>.

Another reminder: you can’t create multiple watches in the same Inotify
instance for the same path.

=cut

sub add {
    my ( $self, $path, %opts ) = @_;

    my @flags = @{ $opts{'flags'} };

    my $mask = 0;
    for my $f (@flags) {
        $mask |= $add_flags{$f} || do {
            die Cpanel::Exception->create_raw("Invalid inotify_add_watch flag: “$f”");
        };
    }

    my $wd = Cpanel::Syscall::syscall(
        'inotify_add_watch',
        $self->{'_fd'},
        $path,
        $mask,
    );

    #TODO: error checking
    if ( $wd < 1 ) {
        die Cpanel::Exception->create_raw("inotify watch descriptor “$wd” means something is wrong?");
    }

    $self->{'_watches'}{$wd} = $path;

    return $wd;
}

=head2 I<OBJ>->remove( DESCRIPTOR )

Just as it sounds: removes a watch from the Inotify instance. The argument is
the descriptor that C<add()> returns.

=cut

sub remove {
    my ( $self, $wd ) = @_;

    Cpanel::Syscall::syscall( 'inotify_rm_watch', $self->{'_fd'}, $wd );

    return;
}

=head2 @events = I<OBJ>->poll()

This does a read on the Inotify instance. Behavior correlates with the
underlying kernel logic (cf. C<man 7 inotify>):

=over

=item A blocking inotify filehandle (default) will block until there’s
an event to report.

=item A C<NONBLOCK> inotify filehandle will receive EAGAIN if there is no
data to be read at the time of the poll, which will prompt an exception.
Thus, if you’re using non-blocking inotify, be sure always to
select/poll/epoll/etc. before you call this method to ensure that there’s
actually something ready to read.

=back

Each event returned is a hash reference with the following members:

=over

=item * C<wd> - The watch descriptor for the event; correlate to the return
from C<add()>.

=item * C<flags> - An array reference (sorted) of flags (e.g., C<MODIFY>)
for the event that prompted this event.

=item * C<name> - cf. C<man 7 inotify>

=item * C<cookie> - cf. C<man 7 inotify>

=back

=cut

sub poll {
    my ($self) = @_;

    Cpanel::Context::must_be_list();

    my $buf = q<>;

    # This will generate an exception if there is no data to read, make sure to select first!
    Cpanel::Autodie::sysread_sigguard( $self->{'_fh'}, $buf, POLL_SIZE() );

    my @events;

    while ( length $buf ) {
        my $evt = $UNPACK_OBJ->unpack_to_hashref( substr( $buf, 0, $UNPACK_SIZE, q<> ) );
        $evt->{'name'} = substr( $buf, 0, delete( $evt->{'len'} ), q<> );
        $evt->{'name'} =~ s<\0+\z><>;    #trailing NULs

        $evt->{'flags'} = _mask_to_flags_ar( delete $evt->{'mask'} );

        push @events, $evt;
    }

    return @events;
}

=head2 I<OBJ>->fileno()

Returns the file number of the inotify handle.

=cut

sub fileno {
    my ($self) = @_;
    return fileno( $self->{'_fh'} );
}

#----------------------------------------------------------------------

sub _mask_to_flags_ar {
    my ($mask) = @_;

    my @flags;
    for my $k ( keys %read_flags ) {
        push @flags, $k if $mask & $read_flags{$k};
    }

    @flags = sort @flags;

    return \@flags;
}

sub _setup_flags {

    #cf. Linux include/uapi/linux/inotify.h
    my %flag_num = (
        ACCESS        => 0x1,      # File was accessed
        MODIFY        => 0x2,      # File was modified
        ATTRIB        => 0x4,      # Metadata changed
        CLOSE_WRITE   => 0x8,      # File opened for writing was closed
        CLOSE_NOWRITE => 0x10,     # File not opened for writing was closed
        OPEN          => 0x20,     # File was opened
        MOVED_FROM    => 0x40,     # File was moved from X
        MOVED_TO      => 0x80,     # File was moved to Y
        CREATE        => 0x100,    # Subfile was created
        DELETE        => 0x200,    # Subfile was deleted
        DELETE_SELF   => 0x400,    # Self was deleted
        MOVE_SELF     => 0x800,    # Self was moved
    );

    %read_flags = (
        %flag_num,

        UNMOUNT    => 0x00002000,    # Backing fs was unmounted
        Q_OVERFLOW => 0x00004000,    # Event queued overflowed ('wd' is -1)
        IGNORED    => 0x00008000,    # Watch was removed
        ISDIR      => 0x40000000,    # event occurred against dir
    );

    %add_flags = (
        %flag_num,

        # special flags
        ONLYDIR     => 0x01000000,    # only watch the path if it is a directory
        DONT_FOLLOW => 0x02000000,    # don't follow a sym link
        EXCL_UNLINK => 0x04000000,    # exclude events on unlinked objects
        MASK_ADD    => 0x20000000,    # add to the mask of an already existing watch
        ONESHOT     => 0x80000000,    # only send event once

        # convenience
        CLOSE => $read_flags{'CLOSE_WRITE'} | $read_flags{'CLOSE_NOWRITE'},
        MOVE  => $read_flags{'MOVED_FROM'} | $read_flags{'MOVED_TO'},
    );

    my $mask = 0;
    $mask |= $_ for values %flag_num;

    $add_flags{'ALL_EVENTS'} = $mask;

    %init1_flag = (
        CLOEXEC  => $Cpanel::Fcntl::Constants::O_CLOEXEC,
        NONBLOCK => $Cpanel::Fcntl::Constants::O_NONBLOCK,
    );

    return;
}

1;
