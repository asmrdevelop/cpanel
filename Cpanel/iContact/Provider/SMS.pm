package Cpanel::iContact::Provider::SMS;

# cpanel - Cpanel/iContact/Provider/SMS.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent 'Cpanel::iContact::Provider::Email';

=encoding utf-8

=head1 NAME

Cpanel::iContact::Provider::SMS - Backend for the SMS iContact module

=head1 SYNOPSIS

    use Cpanel::iContact::Provider::SMS;

    my $notifier = Cpanel::iContact::Provider::SMS->new();
    $notifier->send();


=head1 DESCRIPTION

Provide backend accessor for the SMS iContact module.

=head1 subroutines

=head2 send

Sends off the notification over SMS.

=head3 Input

None

=head3 Output

Truthy value on success, exception on failure.

=cut

sub send {
    my ($self) = @_;

    my %OPTS = %{ $self->{'args'} };

    # We won't be sending any HTML
    delete $OPTS{'html_body'};

    # Since this is a text, we will send the subject only
    # but, we must send the subject as the message body because the subject is truncated
    my $subject = $OPTS{'subject'};
    $OPTS{'text_body'} = \$subject;
    delete $OPTS{'subject'};

    return $self->email_message(%OPTS);
}

1;
