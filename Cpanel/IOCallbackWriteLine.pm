package Cpanel::IOCallbackWriteLine;

# cpanel - Cpanel/IOCallbackWriteLine.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::IOCallbackWriteLine - line buffering, à la IO::Callback

=head1 SYNOPSIS

    my @lines;
    my $fh = Cpanel::IOCallbackWriteLine->new( sub { push @lines, $_[0] } );

    print {$fh} "foo\nbar\nbaz";    # @lines is now: ("foo\n", "bar\n")

    $fh->clear();                   # ("foo\n", "bar\n", "baz")

    $fh->clear();                   # - no change

    print {$fh} 123;                # - doesn’t fire the callback

    undef $fh;                      # ("foo\n", "bar\n", "baz", "123")

=head1 DESCRIPTION

L<IO::Callback> allows chunked writes to a callback function; this module
offers similar functionality but splits the chunks into lines.

There is a C<clear()> method that will send any buffered text into the
callback. (The callback is not called if there is no buffered text.)

Note that C<clear()> is called on C<close()>, and C<close()> is called
on DESTROY.

=cut

#----------------------------------------------------------------------

use parent qw(
  Cpanel::CPAN::IO::Callback::Write
);

use Cpanel::IOCallbackWriteLine::Buffer ();

#----------------------------------------------------------------------

my %BUFFER_OBJ;

sub new {
    my ( $class, $line_callback ) = @_;

    my $buffer_obj = Cpanel::IOCallbackWriteLine::Buffer->new($line_callback);

    my $self = $class->SUPER::new( sub { $buffer_obj->feed( $_[0] ) } );

    $BUFFER_OBJ{$self} = $buffer_obj;

    return $self;
}

sub clear {
    my ($self) = @_;

    $BUFFER_OBJ{$self}->clear();

    return 1;
}

sub CLOSE {
    my ($self) = @_;

    $self->clear();

    delete $BUFFER_OBJ{$self};

    return 1;
}

sub DESTROY {
    my ($self) = @_;

    if ( $BUFFER_OBJ{$self} ) {
        $self->CLOSE();
    }

    return;
}

1;
