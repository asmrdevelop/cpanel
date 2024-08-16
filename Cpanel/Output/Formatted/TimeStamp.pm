package Cpanel::Output::Formatted::TimeStamp;

# cpanel - Cpanel/Output/Formatted/TimeStamp.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Output::Formatted Cpanel::Output::TimeStamp  );

###########################################################################
#
# Method:
#   new
#
# Description:
#   Creates a Cpanel::Output::Formatted::TimeStamp object used to display or trap output
#
# Parameters:
#   'filehandle'       -  Optional: A file handle to write the data to (STDOUT is the default)
#   'parent'           -  Optional: A datastructure that will be passed to the renderer
#                         that is used to display a header or other data to be combined with
#                         message.   See Cpanel::Output::Restore for an example of this use.
#   'timestamp_method' -  Optional: A coderef that returns a timestamp. If this is not
#                         supplied it will just use time().
#
# Exceptions:
#   dies if timestamp_method is supplied but is not a coderef.
#
# Returns:
#   A Cpanel::Output::Formatted::TimeStamp object
#
sub new {
    my ( $class, %OPTS ) = @_;

    my $self = $class->SUPER::new(%OPTS);
    if ( defined $OPTS{'timestamp_method'} ) {

        # If we can't load Cpanel::LoadModule (see the message note below or in Cpanel::Output::message),
        # we shouldn't load Cpanel::Exception either (since it uses Cpanel::LoadModule)
        die "Parameter 'timestamp_method' must be a coderef!" if ref $OPTS{'timestamp_method'} ne 'CODE';
        $self->{'timestamp_method'} = $OPTS{'timestamp_method'};
    }

    return $self;
}

sub _prepend_message {
    return $_[0]->SUPER::_prepend_message() . '[' . ( $_[0]->{'timestamp_method'} ? $_[0]->{'timestamp_method'}->() : time() ) . '] ';
}

1;

__END__
