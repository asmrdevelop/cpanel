package IO::Framed::X::EmptyRead;

=encoding utf-8

=head1 NAME

IO::Framed::X::EmptyRead

=head1 SYNOPSIS

    use Try::Tiny;
    use IO::Framed::Read;

    my $iof = IO::Framed::Read->new( $some_socket );

    try { $iof->read(20) }
    catch {
        if ( try { $_->isa('IO::Framed::Read') } ) { ... }
    };

=head1 DESCRIPTION

Thrown when a read operation returns empty but without an error from the
operating system. This isn’t an *error* so much as just an “exceptional
condition” that so radically changes the application state that it’s
worth throwing on.

You can suppress this error by setting C<allow_empty_read()> on the
L<IO::Framed::Read> instance; otherwise, you should probably always trap
this error so you can cleanly shut things down.

=cut

use strict;
use warnings;

use parent qw( IO::Framed::X::Base );

sub _new {
    my ($class) = @_;

    return $class->SUPER::_new( 'Got empty read; EOF?' );
}

1;
