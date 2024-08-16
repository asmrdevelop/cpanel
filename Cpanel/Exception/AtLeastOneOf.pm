package Cpanel::Exception::AtLeastOneOf;

# cpanel - Cpanel/Exception/AtLeastOneOf.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

#Metadata properties:
#   params    - should be an arrayref of parameter names that we need at leats one of#
sub _default_phrase {
    my ($self) = @_;

    # If $self->{_metadata}{params} is not an array ref already then this is being called wrong. Do we have exceptions for use by exceptions? :|
    return Cpanel::LocaleString->new( "You must provide information via at least one of these: [list_or,_1]", $self->{_metadata}{params} );
}

1;
