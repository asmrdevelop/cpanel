package Cpanel::RedirectFH;

# cpanel - Cpanel/RedirectFH.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::RedirectFH - Temporarily redirect one output filehandle to another.

=head1 SYNOPSIS

    {
        my $redir = Cpanel::RedirectFH->new( \*STDOUT => \*STDERR );

        syswrite( \*STDOUT, 'hahaha' );     #sent to STDERR
    }

    syswrite( \*STDOUT, 'hohoho' );     #sent to STDOUT

=head1 DESCRIPTION

Instances of this class cause input to one filehandle to be sent to the other
filehandle. When the object is destroyed, the redirection is removed.

This is useful, e.g., as a much cheaper substitute for L<Capture::Tiny>.

=head1 METHODS

=head2 $OBJ = I<CLASS>->new( $FROM_FH, $TO_FH )

Instantiates this class.

=cut

sub new {
    my ($class) = @_;

    open( my $orig_from, '>&', $_[1] ) or die "$class: failed to save “from”: $!";
    open( $_[1],         '>&', $_[2] ) or die "$class: failed to redirect: $!";

    return bless [ $_[1], $orig_from ], $class;
}

sub DESTROY {
    my ($self) = @_;

    open $self->[0], '>&', $self->[1] or die "$self: failed to restore original “from”: $!";

    return;
}

1;
