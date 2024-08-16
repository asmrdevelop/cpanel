package Cpanel::CommentKiller;

# cpanel - Cpanel/CommentKiller.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

sub new ($class) {
    return bless { 'ml_terminator' => undef }, $class;
}

my %terminator_map = (
    '/*' => '*/',
);

my $start_multiline_comment = sub ( $self, $rline, $token ) {
    while ( index( $rline, $terminator_map{$token} ) > -1 ) {    # Kill sameline
        $rline = substr( $rline, 0, index( $rline, $token ) ) . substr( $rline, index( $rline, $terminator_map{$token} ) + 2 );
    }
    if ( index( $rline, $token ) > -1 ) {                        # bayonet the survivors
        $self->{'ml_terminator'} = $terminator_map{$token};
        $rline = substr( $rline, 0, index( $rline, $token ) );
    }
    return $rline;
};

my $end_multiline_comment = sub ( $self, $rline, $token ) {
    if ( index( $rline, '*/' ) > -1 ) {
        undef $self->{'ml_terminator'};
        return substr( $rline, index( $rline, '*/' ) + 2 );
    }
    return;                                                      #still in comment
};

my $oneline_comment = sub ( $self, $rline, $token ) {
    return substr( $rline, 0, index( $rline, $token ) );
};

my %token_map = (
    '/*' => $start_multiline_comment,
    '//' => $oneline_comment,
    '#'  => $oneline_comment,
);

sub parse {
    my ( $self, $rline ) = @_;
    return '' unless length $rline;

    if ( defined $self->{'ml_terminator'} ) {
        $rline = $end_multiline_comment->( $self, $rline, $self->{'ml_terminator'} );
        return unless length $rline;
    }

    # Do it by order tokens encountered, *as that is important*
    my %positions_map = map { index( $rline, $_ ) => $_ } keys %token_map;
    while ( my ($pos) = sort keys(%positions_map) ) {
        my $key = delete $positions_map{$pos};
        next if ( $pos == -1 );
        $rline = $token_map{$key}->( $self, $rline, $key );

        # Rescan if modifications were made.
        %positions_map = map { index( $rline, $_ ) => $_ } keys %token_map;
    }
    return $rline;
}

1;
