package Cpanel::Parser::Callback;

# cpanel - Cpanel/Parser/Callback.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use base 'Cpanel::Parser::Base';

use Cpanel::Exception ();

###########################################################################
#
# Method:
#   new
#
# Description:
#   Creates a Cpanel::Parser::Callback
#   that is used to pass lines of data to be parsed to
#   a coderef
#
# Parameters:
#   'callback'              -  The coderef that will receieve each line of data.
#
# Returns:
#   A Cpanel::Parser::Callback object
#
sub new {
    my ( $class, %OPTS ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'callback' ] ) if !$OPTS{'callback'};
    die Cpanel::Exception::create( 'InvalidParameter', 'The parameter “[_1]” must be a coderef.', ['callback'] ) if ref $OPTS{'callback'} ne 'CODE';

    my $self = { 'callback' => $OPTS{'callback'} };

    return bless $self, $class;
}

###########################################################################
#
# Method:
#   process_line
#
# Description:
#   Pass a single line of data to the callback.
#
# Parameters:
#   $line         - The line of data
#
# Returns:
#   The return value from the callback
#
sub process_line {
    my ( $self, $line ) = @_;

    return $self->{'callback'}->($line);
}

###########################################################################
#
# Method:
#   finish
#
# Description:
#   Sends the remaining data to process_line
#   to ensure all data is processed.  This
#   is generally to handle the end of a data
#   stream that is not new line terminated
#
# Parameters:
#   none
#
# Returns:
#   The return value from the callback or 1 if there is no data
#
sub finish {
    my ($self) = @_;

    if ( length $self->{'_buffer'} ) {
        return $self->process_line( $self->{'_buffer'} );
    }

    return 1;
}

1;
