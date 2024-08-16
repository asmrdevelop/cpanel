package Cpanel::iContact::Provider::Email;

# cpanel - Cpanel/iContact/Provider/Email.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent 'Cpanel::iContact::Provider';

###########################################################################
#
# Method:
#   send
#
# Description:
#   This implements sending email messages.  For arguments to create
#   a Cpanel::iContact::Provider::Email object, see Cpanel::iContact::Provider.
#   The html content is preferred if available.
#
# Exceptions:
#   This module throws on failure
#
# Returns: 1
#
sub send {
    my ($self) = @_;

    return unless -e '/etc/.whostmgrft';    # Sending emails is impossible until root has been setup in the first login.

    return $self->email_message(
        %{ $self->{'args'} },
        'attach_files' => $self->{'attach_files'}
    );
}

1;
