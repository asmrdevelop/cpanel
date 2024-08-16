package Cpanel::Output::Multi;

# cpanel - Cpanel/Output/Multi.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent 'Cpanel::Output';

use Cpanel::Exception ();

###########################################################################
#
# Method:
#   new
#
# Description:
#   Creates a Cpanel::Output::Multi object used to emulate
#   a Cpanel::Output object and pass the calls to each
#   object that is contained within.
#
# Parameters:
#   'output_objs'             - An arrayref of Cpanel::Output objects
#
# Exceptions:
#   none
#
# Returns:
#   A Cpanel::Output::Multi object
#
#
sub new {
    my ( $class, %OPTS ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'output_objs' ] ) if !$OPTS{'output_objs'};

    my $self = { 'output_objs' => $OPTS{'output_objs'} };
    bless $self, $class;

    return $self;
}

#
# out is a wrapper to call the same method in the
# Cpanel::Output object (see Cpanel/Output.pm) as
# the arguments to this function are opaque to this
# function
#
sub out {
    $_->out( @_[ 1 .. $#_ ] ) for @{ $_[0]->{'output_objs'} };
    return 1;
}

#
# warn is a wrapper to call the same method in the
# Cpanel::Output object (see Cpanel/Output.pm) as
# the arguments to this function are opaque to this
# function
#
sub warn {
    $_->warn( @_[ 1 .. $#_ ] ) for @{ $_[0]->{'output_objs'} };
    return 1;
}

#
# success is a wrapper to call the same method in the
# Cpanel::Output object (see Cpanel/Output.pm) as
# the arguments to this function are opaque to this
# function
#
sub success {
    $_->success( @_[ 1 .. $#_ ] ) for @{ $_[0]->{'output_objs'} };
    return 1;
}

#
# error is a wrapper to call the same method in the
# Cpanel::Output object (see Cpanel/Output.pm) as
# the arguments to this function are opaque to this
# function
#

sub error {
    $_->error( @_[ 1 .. $#_ ] ) for @{ $_[0]->{'output_objs'} };
    return 1;
}

#
# message is a wrapper to call the same method in the
# Cpanel::Output object (see Cpanel/Output.pm) as
# the arguments to this function are opaque to this
# function
#

sub message {
    $_->message( @_[ 1 .. $#_ ] ) for @{ $_[0]->{'output_objs'} };
    return 1;
}

# We need to increase/decrease indent level in the Multi
# object as well as some callers track this
sub decrease_indent_level {
    $_->decrease_indent_level( @_[ 1 .. $#_ ] ) for @{ $_[0]->{'output_objs'} };
    return $_[0]->SUPER::decrease_indent_level();
}

sub increase_indent_level {
    $_->increase_indent_level( @_[ 1 .. $#_ ] ) for @{ $_[0]->{'output_objs'} };
    return $_[0]->SUPER::increase_indent_level();
}

sub reset_indent_level {
    $_->reset_indent_level( @_[ 1 .. $#_ ] ) for @{ $_[0]->{'output_objs'} };
    return $_[0]->SUPER::reset_indent_level();
}

1;

__END__
