
# cpanel - Cpanel/Exception/TicketSupport/JsonApi.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Exception::TicketSupport::JsonApi;
use strict;
use warnings;

=head1 Name

Cpanel::Exception::TicketSupport::JsonApi

=head1 Description

This exception class may be used when a request to the ticket system API fails
in a way that provides a meaningful error back via JSON reply. The intent is
that you will take the JSON reply from the ticket system and feed it into this
module via the error_info field.

=head1 Metadata parameters

url - String - The URL that was requested

method - String - The method that was used for the request (e.g., GET, POST, etc.)

status - Integer - The HTTP status that was returned by the server

error_info - Hash ref - The error information returned by the server in the
JSON reply. As of this writing, the only field from this data that's actually
used by this class is 'message', which comes from the Ticket System API error
response.

=cut

use parent 'Cpanel::Exception';

use Cpanel::LocaleString ();

sub _default_phrase {
    my ($self) = @_;

    my $error_info = $self->get('error_info');

    # 'message' is a field provided in Ticket System API error responses regardless of API version
    my $message = $error_info->{message};

    return Cpanel::LocaleString->new(
        'The ticket system [asis,API] “[_1]” request to “[_2]” failed with a “[_3]” status code and the following error message: [_4]',
        ( map { $self->get($_) } qw( method url status ) ), $message
    );
}

1;
