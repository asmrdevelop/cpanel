package Cpanel::Forked;

# cpanel - Cpanel/Forked.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Forked - represent a forked process

=head1 SYNOPSIS

    {
        my $forked = Cpanel::Forked->new( sub { ... } );

        #... child process is automatically killed if it
        #is still around
    }

=head1 DESCRIPTION

This class performs automatic “garbage collection” of child
processes, which can be useful to ensure that we never get unreaped
children.

=head1 METHODS

=cut

use strict;
use warnings;

use Cpanel::ForkAsync ();
use Cpanel::LoadFile  ();

=head2 I<CLASS>->new( SUBROUTINE )

Instantiates this class. A child process is immediately fork()ed, and
the SUBROUTINE is executed in that child process.

The returned object will, when DESTROYed, check to see if the original
process is still around and, if so, kill it via
C<Cpanel::Kill::Single>. To guard against inadvertently killing a process
that happens to have the same PID but is actually a different process,
this function tracks the process’s start time as well as the PID.

=cut

sub new {
    my ( $class, $sub ) = @_;

    die "Need coderef, not “$sub”!" if 'CODE' ne ref $sub;

    my $pid = Cpanel::ForkAsync::do_in_child($sub);

    my %self = (
        ppid       => $$,
        cpid       => $pid,
        start_time => _get_pid_start_time($pid),
    );

    return bless \%self, $class;
}

=head2 I<OBJ>->pid()

Returns the child PID.

=cut

sub pid {
    my ($self) = @_;
    return $self->{'cpid'};
}

=head2 I<OBJ>->terminate()

Terminates the child process.

=cut

sub terminate {
    my ($self) = @_;

    require Cpanel::Kill::Single;
    Cpanel::Kill::Single::safekill_single_pid( $self->{'cpid'} );

    return;
}

=head1 IMPLEMENTATION NOTES

Currently the implementation depends on F</proc>, which is a bit slow
for at least some production deployments.

It would be great to find a faster way to get a unique-ish, non-recurring
quality of a process than reading F</proc> to get the process’s start time.
If we can do that, then this will be more useful for production.

Even as it stands, though, reading F</proc> a couple times shouldn’t be
too bad for most uses.

=head1 SEE ALSO

L<Cpanel::ForkAsync>, which this module uses internally.

=cut

#----------------------------------------------------------------------

#This may not be fast enough for every production case, but it’s
#at least useful in testing.
sub _get_pid_start_time {
    my ($pid) = @_;

    my $proc_stat = Cpanel::LoadFile::load_if_exists("/proc/$pid/stat");

    return $proc_stat && ( split m<\s+>, $proc_stat )[21] // q<>;
}

sub DESTROY {
    my ($self) = @_;

    return if $$ != $self->{'ppid'};
    return if !kill( 'ZERO', $self->{'cpid'} );

    my $start_time = _get_pid_start_time( $self->{'cpid'} );

    if ( $start_time eq $self->{'start_time'} ) {
        warn sprintf "%s instance (PID %d) still has an active subprocess (PID %d)! Ending …", ref($self), $self->{'ppid'}, $self->{'cpid'};

        $self->terminate();
    }

    return;
}

1;
