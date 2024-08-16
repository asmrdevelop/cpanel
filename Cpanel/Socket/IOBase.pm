package Cpanel::Socket::IOBase;

# cpanel - Cpanel/Socket/IOBase.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Socket::IOBase - Base class for IO::Socket::* wrapper classes

=head1 SYNOPSIS

See subclasses.

=head1 DESCRIPTION

This module wraps the C<new()> method with logic to create an exception
when there is a failure. L<IO::Socket> doesn’t provide very reliable error
reports, so this takes care of that.

Note that nothing but C<new()> is wrapped; you’ll still need to use
L<Cpanel::Autodie::*> modules (or Perl’s own L<autodie>) to get automatic
error reporting on I/O operations.

=cut

use Cpanel::Exception ();

=head1 METHODS

=head2 $socket = I<CLASS>->new(...)

See the individual class for documentation on the parameters this
expects. It will always either throw an exception or return a socket.

=cut

sub new {    ##no critic qw( RequireArgUnpacking )
    my $class = shift;

    #IO::Socket sometimes likes to call new() on an object,
    #so we need to accept either an object or the class name.
    my $pkg = ( ref $class ) || $class;

    local ( $!, $@ );
    my $dollar_at;

    my $self = eval {
        my $obj = $class->_IO_SUPERCLASS()->can('new')->( $pkg, @_ );
        $dollar_at = $@;
        $obj;
    };

    if ( !$self ) {

        #For now, leave this as a simple error. If we want to make it more
        #query-able, we can do that later.
        #
        #NOTE: IO::Socket’s error reporting is very clumsy. It writes some
        #information to $@, some to $!. In the interest of completeness, then,
        #these error messages contain both.
        my @errs = grep { length } $@, $!, $dollar_at;
        $_ = "[$_]" for @errs;

        die Cpanel::Exception->create_raw(
            "$class connection (@_) failure: @errs",
            {
                error => $!,
            },
        );
    }

    return $self;
}

=head1 HOW TO MAKE YOUR OWN SUBCLASS

Have your subclass inherit from both the present module and from the
relevant L<IO::Socket> subclass.

Also define an C<_IO_SUPERCLASS()> constant (or function) that returns that
same L<IO::Socket> subclass.

=cut

1;
