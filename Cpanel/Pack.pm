package Cpanel::Pack;

# cpanel - Cpanel/Pack.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=encoding utf-8

=head1 NAME

Cpanel::Pack - conveniences around Perl’s C<pack()> function

=head1 SYNOPSIS

    use Cpanel::Pack ();

    my $t_obj = Cpanel::Pack->new( [
        qw(
            foo     C
            bar     C
            baz     a*
        )
    ] );

    $t_obj->sizeof() # returns 3

    $t_obj->malloc() # returns a scalar value the size of the data
                     # structure provided at initialization time

    # Yields:
    # {
    #    foo => 1,
    #    bar => 9,
    #    baz => 'haha',
    # }
    my $unpacked_hr = $t_obj->unpack_to_hashref( "\x01\x09haha" );

    # The inverse of the above.
    my $buf = $t_obj->pack_from_hashref( $unpacked_hr );

=cut

use strict;

sub new {
    my ( $class, $template_ar ) = @_;

    if ( @$template_ar % 2 ) {
        die "Cpanel::Pack::new detected an odd number of elements in hash assignment!";
    }

    my $self = bless {
        'template_str' => '',
        'keys'         => [],
    }, $class;

    my $ti = 0;
    while ( $ti < $#$template_ar ) {
        push @{ $self->{'keys'} }, $template_ar->[$ti];
        $self->{'template_str'} .= $template_ar->[ 1 + $ti ];
        $ti += 2;
    }

    return $self;
}

# $_[0]: self
# $_[1]: buffer
sub unpack_to_hashref {    ## no critic (RequireArgUnpacking)
    my %result;
    @result{ @{ $_[0]->{'keys'} } } = unpack( $_[0]->{'template_str'}, $_[1] );
    return \%result;
}

sub pack_from_hashref {
    my ( $self, $opts_ref ) = @_;
    no warnings 'uninitialized';
    return pack( $self->{'template_str'}, @{$opts_ref}{ @{ $self->{'keys'} } } );
}

sub sizeof {
    my ($self) = @_;
    return ( $self->{'sizeof'} ||= length pack( $self->{'template_str'}, () ) );
}

sub malloc {
    my ($self) = @_;

    return pack( $self->{'template_str'} );
}

1;
