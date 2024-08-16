package IO::Framed::X::EmptyWrite;

=encoding utf-8

=head1 NAME

IO::Framed::X::EmptyWrite

=head1 SYNOPSIS

    use Try::Tiny;
    use IO::Framed::Write;

    my $iof = IO::Framed::Write->new( $some_socket );

    try { $iof->write(q<>) }
    catch {
        if ( try { $_->isa('IO::Framed::Read') } ) { ... }
    };

=head1 DESCRIPTION

Thrown when empty string or undef is given to C<write()>.

=cut

use strict;
use warnings;

use parent qw( IO::Framed::X::Base );

1;
