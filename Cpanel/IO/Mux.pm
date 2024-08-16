package Cpanel::IO::Mux;

# cpanel - Cpanel/IO/Mux.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 NAME

Cpanel::IO::Mux - A small, simple I/O multiplexer wrapper to
L<select()|perlfunc/select>

=head1 DESCRIPTION

C<Cpanel::IO::Mux> is a small, fast object-oriented I/O multiplexer that acts as
a wrapper to L<select()|perlfunc/select>.  Unlike L<IO::Select>, this
module acts as a very thin abstraction to L<select()|perlfunc/select>, allowing
more flexibility while needing fewer select(2) calls for many operations.

=head1 CREATING A MULTIPLEXER

=over

=item C<Cpanel::IO::Mux-E<gt>new(%opts)>

Create a new I/O multiplexer object.  The arguments in C<%opts> specify the
initial set of file handles to check for I/O readiness, as well as an optional
timeout value to pass to L<select()|perlfunc/select>.

=over

=item C<read>

An I<ARRAY> reference of Perl file handles that specifies the initial set that
should be checked for read readiness.

=item C<write>

An I<ARRAY> reference of Perl file handles that specifies the initial set that
should be checked for write readiness.

=item C<err>

An I<ARRAY> reference of Perl file handles that should be checked for error
conditions.

=item C<timeout>

An integer or floating point value specifying, in seconds, the maximum amount of
time to be spent waiting for file handles to become ready.  When unspecified or
set to C<undef>, checks for readiness will block until any number of handles
become ready.

=back

=back

=cut

sub new {
    my ( $class, %opts ) = @_;

    my $ret = bless {
        'read'    => "\x0",
        'write'   => "\x0",
        'err'     => "\x0",
        'timeout' => $opts{'timeout'},
        'class'   => $class,
    }, $class;

    foreach my $set ( 'read', 'write', 'err' ) {
        next unless $opts{$set};

        die("File handle set '$set' not an ARRAY ref") unless ref( $opts{$set} ) eq 'ARRAY';

        #
        # Record the file descriptor number of each handle in the current set
        # into the bitfield in the return object corresponding to the current
        # set.
        #
        foreach my $handle ( @{ $opts{$set} } ) {
            $ret->set( $handle, $set );
        }
    }

    $ret->{'empty'} = _empty( @{$ret}{qw( read write err )} );

    return $ret;
}

#
# Returns true if each bit field stored in a Perl string has no bits set.
#
sub _empty {
    my (@sets) = @_;

    #
    # Using vec() to set bit values in a Perl string makes the string grow to
    # the appropriate number of bytes to hold the highest bit value.  Also,
    # using vec() to clear bit values does not shrink the string.  So, this is
    # unfortunately the best and quickest way I came up with to test a bit field
    # stored in a Perl string, of any size, to be nonzero, or empty, in the
    # context of file descriptors.
    #
    foreach my $set (@sets) {
        return 0 if grep { $_ } unpack( 'C*', $set );
    }

    return 1;
}

=head1 WAITING FOR FILE HANDLE READINESS

=over

=item C<$ready = $mux-E<gt>select()>

Wait for the file handles set up in C<$mux> to become ready for reading,
writing, or for those that have error conditions.  Another instance of
C<Cpanel::IO::Mux> is returned; one should use C<$ready-E<gt>isset()> to test
which file handles are ready.

C<$ready> will contain the following additional values returned by
C<select()|perlfunc/select>:

=over

=item C<found>

The number of file descriptors found to be ready.

=item C<timeleft>

Depending on the operating system, this value may be C<undef>, or may contain
the amount of time left since the start of the C<$mux-E<gt>select()> call until
the C<timeout> value passed in the constructor is reached.

=back

=cut

sub select {
    my ($self) = @_;

    #
    # If there's nothing to be select()ed, then return nothing.
    #
    return if $self->{'empty'};
    #
    # Perform the select(2) call, storing values set into their own hash for
    # subsequent checking.
    #
    #
    my %ready;
    my @selected = select(
        $ready{'read'}  = $self->{'read'},
        $ready{'write'} = $self->{'write'},
        $ready{'err'}   = $self->{'err'},
        $self->{'timeout'}
    );

    die("Unable to select(): $!") if ( $selected[0] < 0 );

    @{ready}{ 'found', 'timeleft' } = @selected;

    return bless \%ready, $self->{'class'};
}

sub _get_fileno {
    my ($handle) = @_;
    my $fileno = fileno($handle) or die('File not open');
    return $fileno;
}

=back

=head1 TESTING FOR A READY FILE DESCRIPTOR

After a successful C<$mux-E<gt>select()> call, the following can be used to test
for specific file handles in C<$ready> that are indeed ready.

=over

=item C<$ready-E<gt>isset($handle, $set)>

Check to see if the file handle in C<$handle> is ready in one of the C<read>,
C<write>, or C<err> sets, as specified in C<$set>.

=back

=cut

sub isset {
    my ( $self, $handle, $set ) = @_;
    return vec( $self->{$set}, _get_fileno($handle), 1 ) == 1;
}

sub is_fileno_set {

    # my ( $self, $fileno, $set ) = @_;
    return vec( $_[0]->{ $_[2] }, $_[1], 1 ) == 1;
}

=head1 ADDING AND DROPPING FILE HANDLES TO WAIT FOR

The following methods can be used on the multiplexer object to specify which
file handles to wait for on the next C<$mux-E<gt>select()> call.

=over

=item C<$mux-E<gt>set($handle, $set)>

Add C<$handle> to the list of file handles to wait for to one of C<read>,
C<write> or C<err>, as specified in C<$set>.

=cut

sub set {
    my ( $self, $handle, $set ) = @_;
    vec( $self->{$set}, _get_fileno($handle), 1 ) = 1;
    $self->{'empty'} = _empty( @{$self}{qw( read write err )} );
    return;
}

=item C<$mux-E<gt>clear($handle, $set)>

Drop C<$handle> from the list of file handles to wait for from one of C<read>,
C<write> or C<err>, as specified in C<$set>.

=back

=cut

sub clear {
    my ( $self, $handle, $set ) = @_;
    vec( $self->{$set}, _get_fileno($handle), 1 ) = 0;
    $self->{'empty'} = _empty( @{$self}{qw( read write err )} );
    return;
}

1;

__END__

=head1 CAVEATS

As with any usage of L<select()|perlfunc/select>, unbuffered file I/O should
always be used, as provided by L<sysread()|perlfunc/sysread> and
L<syswrite()|perlfunc/syswrite>.

=head1 COPYRIGHT

Copyright (c) 2013, cPanel, inc.  Distributed under the terms of the cPanel
license.  Unauthorized copying is prohibited.
