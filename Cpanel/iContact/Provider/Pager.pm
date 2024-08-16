package Cpanel::iContact::Provider::Pager;

# cpanel - Cpanel/iContact/Provider/Pager.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent 'Cpanel::iContact::Provider::Email';

###########################################################################
#
# Method:
#   send
#
# Description:
#   This implements sending pager (or SMS) messages.  For arguments to create
#   a Cpanel::iContact::Provider::Pager object, see Cpanel::iContact::Provider.
#   The plaintext context is preferred if available.
#
# Exceptions:
#   This module throws on failure
#
# Returns: 1
#
sub send {
    my ($self) = @_;

    my %OPTS = %{ $self->{'args'} };

    delete $OPTS{'html_body'} if length $OPTS{'text_body'};

    return $self->email_message(%OPTS);
}

1;
