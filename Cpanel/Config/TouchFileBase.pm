package Cpanel::Config::TouchFileBase;

# cpanel - Cpanel/Config/TouchFileBase.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Config::TouchFileBase - base class for touch file access

=head1 SYNOPSIS

    package TheSubclass;

    use parent qw(Cpanel::Config::TouchFileBase);

    use constant _TOUCH_FILE => '/path/to/touch/file';

    package main;

    #is_on() returns 1 if the path is a file and 0 if it’s not there.
    #Any other state, including a failure to ascertain one of those states,
    #will prompt an exception.
    #
    print "Flag is on? " . TheSubclass->is_on();

    TheSubclass->set_on();  #returns 1, throws on error

    TheSubclass->set_off(); #returns 1, throws on error

    TheSubclass->set_off(); #...but this time, since it was a no-op, returns 0

=head1 DESCRIPTION

This simple base class encapsulates interaction with touch files. It throws
Cpanel::Exception objects to indicate errors.

=cut

use Cpanel::Autodie   ();
use Cpanel::Exception ();

#For testing.
sub _TOUCH_FILE { die Cpanel::Exception::create('AbstractClass') }

sub is_on {
    my ( $self, @args ) = @_;

    #Do NOT use -e here; we should die() on any error state besides ENOENT.
    my $exists = Cpanel::Autodie::exists( $self->_TOUCH_FILE(@args) );

    if ( $exists && !-f _ ) {
        die Cpanel::Exception->create( '“[_1]” exists but is not a file!', [ $self->_TOUCH_FILE(@args) ] );
    }

    return $exists;
}

#Returns 1 if it created the file or 0 if it was already there.
sub set_on {
    my ( $self, @args ) = @_;

    my $path = $self->_TOUCH_FILE(@args);

    require Cpanel::FileUtils::Touch;

    return Cpanel::FileUtils::Touch::touch_if_not_exists($path);
}

#Returns 1 if it unlinked the file or 0 if it wasn’t there.
sub set_off {
    my ( $self, @args ) = @_;

    return Cpanel::Autodie::unlink_if_exists( $self->_TOUCH_FILE(@args) );
}

1;
