package Cpanel::Resolvers::Check::Status;

# cpanel - Cpanel/Resolvers/Check/Status.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# To indicate an error-free status:
#
#   Cpanel::Resolvers::Check::Status->new();
#
# ...otherwise, pass in a list of error states.
# It’s unsure for now whether there can be non-mutually-exclusive
# error states, so currently this is implemented as a list, but
# we only know of cases where there’d be one status at a time (as of
# March 2016).
#----------------------------------------------------------------------

use strict;
use warnings;

use Cpanel::Exception ();

my @KNOWN_ERRORS = (
    'missing',    #no resolvers

    'failed',     #all resolvers down

    'unreliable', #at least one resolver has a problem

    'slow',       #at least one resolver is taking a “long time”
                  #...whatever that means! :)
);

sub new {
    my ( $class, @errors ) = @_;

    _validate_error($_) for @errors;

    return bless \@errors, $class;
}

sub is_ok {
    my ($self) = @_;

    return !@$self ? 1 : 0;
}

sub error_is {
    my ( $self, $error ) = @_;

    _validate_error($error);

    return scalar grep { $_ eq $error } @$self;
}

sub _validate_error {
    my ($error) = @_;

    if ( !grep { $_ eq $error } @KNOWN_ERRORS ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid error state. Use one of the following: [join,~, ,_2].', [ $error, \@KNOWN_ERRORS ] );    ## no extract maketext
    }

    return;
}

1;
