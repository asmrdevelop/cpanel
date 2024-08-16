package Cpanel::IOCallbackWriteLine::Buffer;

# cpanel - Cpanel/IOCallbackWriteLine/Buffer.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::IOCallbackWriteLine::Buffer

=head1 SYNOPSIS

    my $liner = Cpanel::IOCallbackWriteLine::Buffer->new( sub ($line) {
        print "line: $line";
    } );

    # This will cause "line 1\n" and "line 2\n" to print.
    # Since "line 3" lacks a trailing newline, it will NOT print yet.
    $liner->feed( join( "\n", 'line 1', 'line 2', 'line 3' ) );

    # This will cause "line 3line 4\n" to print.
    $liner->feed( join( "\n", 'line 4', 'line 5' ) );

    # This will cause "line 5" to print (without a newline).
    $liner->clear();

=head1 DESCRIPTION

This little module provides an easy way to split a byte stream into lines.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Destruct::DestroyDetector';

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new( $ON_LINE_CR )

Instantiates this class. $ON_LINE_CR is a coderef that receives each line
(including the trailing newline) of the content given to C<feed()> below
as well as the last chunk when C<clear()> is called.

=cut

sub new ( $class, $line_callback ) {

    return bless [ q<>, $line_callback ], $class;
}

=head2 I<OBJ>->feed( $BYTES )

Augments I<OBJ>’s internal buffer, which is then split on each newline
and fed into the callback given to C<new()>. Trailing content is B<not>
given to the callback.

=cut

my $recsep_idx;

# No signature because this gets called in tight loops.
sub feed {    # ($self, $new_str)

    my $self = $_[0];

    substr( $self->[0], length( $self->[0] ), 0, $_[1] );

    while ( -1 != ( $recsep_idx = index( $self->[0], $/ ) ) ) {
        $self->[1]->( substr( $self->[0], 0, length($/) + $recsep_idx, q<> ) );
    }

    return 1;
}

=head2 I<OBJ>->clear()

Empties out I<OBJ>’s internal buffer and feeds the result to the callback
given to C<new()>. Because C<feed()> will have already given any complete
lines, this result given to the callback will B<lack> a trailing newline.

=cut

sub clear ($self) {

    if ( length $self->[0] ) {
        $self->[1]->( substr( $self->[0], 0, length( $self->[0] ), q<> ) );
    }

    return 1;
}

sub DESTROY ($self) {

    if ( length $self->[0] ) {

        # Don’t forget to clear()!
        warn "DESTROY with content left in buffer: “$self->[0]”";
    }

    $self->SUPER::DESTROY();

    return;
}

1;
