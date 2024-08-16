package Cpanel::Buffer::Line;

# cpanel - Cpanel/Buffer/Line.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

my $SIZE = 65536;

=encoding utf8

=head1 NAME

Cpanel::Buffer::Line - Drop-in replacement for readline() with a maximum buffer
size

=head1 SYNOPSIS

    use Cpanel::Buffer::Line ();

    my $buf = Cpanel::Buffer::Line->new;

    while ( defined( my $line = $buf->readline( \*STDIN ) ) ) {
        chomp $line;

        print "Got line '$line'\n";
    }

=head1 DESCRIPTION

L<Cpanel::Buffer::Line> provides a safe way to read streams containing
arbitrarily long lines, up to a specified limit, so as to avoid certain
possible situations due to memory exhaustion from buffering very large lines.

=head1 INSTANTIATION

=over

=item C<Cpanel::Buffer::Line-E<gt>new(I<%args>)>

Create a new line buffer.  The following arguments are accepted:

=over

=item B<size>

Specifies the maximum size of the line buffer.  Default is C<65536>.

=back

=back

=cut

sub new ( $class, %args ) {

    $args{'size'} ||= $SIZE;

    return bless {
        'buf'  => '',
        'size' => $args{'size'}
    }, $class;
}

=head1 READING LINES

=over

=item C<$buf-E<gt>readline()>

Read and return a line from the stream.

This function fills the line buffer to maximum capacity, and searches for the
next newline.  If a newline cannot be found, and the buffer is at capacity,
then the function will die() with a message indicating this condition.

=back

=cut

sub readline ( $self, $fh ) {

    my $free = $self->{'size'} - length( $self->{'buf'} ) % $self->{'size'};

    if ($free) {
        my $tmp;

        my $readlen = read $fh, $tmp, $free;

        $self->{'buf'} .= $tmp if $readlen > 0;
    }

    my $length = length $self->{'buf'};
    my $index  = index $self->{'buf'}, "\n";

    if ( $length == $self->{'size'} && $index < 0 && !eof($fh) ) {
        die 'Buffer size exceeded';
    }
    elsif ( $length > 0 && $length <= $self->{'size'} && $index < 0 && eof($fh) ) {
        my $rest = $self->{'buf'};
        $self->{'buf'} = '';
        return $rest;
    }
    elsif ( $length == 0 ) {
        return;
    }

    my $offset = $index + 1;
    my $line   = substr $self->{'buf'}, 0, $offset;
    my $end    = $length - $index;

    $self->{'buf'} = substr $self->{'buf'}, $offset, $end;

    return $line;
}

=head1 COPYRIGHT

Copyright (c) 2022 cPanel, L.L.C.  Unauthorized copying is prohibited.

=cut

1;
