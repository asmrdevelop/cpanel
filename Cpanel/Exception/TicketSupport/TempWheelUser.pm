
# cpanel - Cpanel/Exception/TicketSupport/TempWheelUser.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Exception::TicketSupport::TempWheelUser;
use strict;
use warnings;

=head1 Name

Cpanel::Exception::TicketSupport::TempWheelUser

=head1 Description

This exception class is used to report problems related to the creation of
a temporary wheel user granting SSH access to the cPanel support staff.

=head1 Metadata parameters

operation - The name of the operation being performed (freeform, but should probably be one word)
This must not include any translated text.

errortype - The name of the error type (freeform, but should probably be one word).
This must not include any translated text.

errormsg - The error message. It's OK for this to be a translated message if needed.

=cut

use parent 'Cpanel::Exception';

use Cpanel::LocaleString ();

sub _default_phrase {
    my ($self) = @_;

    my $operation = $self->get('operation');
    my $errortype = $self->get('errortype');
    my $errormsg  = $self->get('errormsg');

    return Cpanel::LocaleString->new(
        'The temporary wheel user “[_1]” operation failed with a “[_2]” error: [_3]',
        $operation,
        $errortype,
        $errormsg,
    );
}

sub errortype {
    my ($self) = @_;
    return $self->get('errortype');
}

1;
