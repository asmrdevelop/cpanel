package Cpanel::Exception::HTTP::Server;

# cpanel - Cpanel/Exception/HTTP/Server.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw(
  Cpanel::Exception::Base::HasUrl
  Cpanel::Exception::HTTP
);

use Cpanel::LocaleString ();

# If the server sent back an error with a JSON body, we want to do our best
# (within reason) to allow the entire response to be logged. Otherwise the
# log message may completely leave out the information about what failed.
our $MAX_LENGTH_FOR_JSON = 512;

# For 599 (the psedudo HTTP status code used by HTTP::Tiny for some non-HTTP
# errors), we can be fairly confident that the body is plain text describing
# the error, so allow a bit more to be shown.
our $MAX_LENGTH_FOR_599 = 128;

# In a normal HTTP response, we don't necessarily know if the body is going
# to be meaningful for display, so only include the first 32 bytes.
our $MAX_LENGTH_FOR_OTHER = 32;

=head1 Name

Cpanel::Exception::HTTP::Server

=head1 Description

This exception class means that an error occurred with an HTTP
request, and the problem had specifically to do with something
that happened on the remote server, not just a general connection
problem. For example, this class would be suitable for use when
you get a 500 Internal Server Error or a 404 Not Found, but it
would not be suitable for use if you get a Connection Refused
error when trying to connect.

=head1 Metadata parameters

All are required:

method

content     - NB: matches HTTP::Tiny::UA::Response

url         - " " "

status      - " " "

reason      - " " "

headers     - " " "

=head1 Accessors

All of the parameters have read-only accessors of the same names
available.

=head1 See also

Cpanel::Exception::HTTP

=cut

sub _default_phrase {
    my ($self) = @_;

    my $max_length = $MAX_LENGTH_FOR_OTHER;
    if ( '599' eq $self->get('status') ) {
        $max_length = $MAX_LENGTH_FOR_599;
    }
    elsif ( ( $self->get('content_type') || '' ) =~ m{^application/json\b} ) {
        $max_length = $MAX_LENGTH_FOR_JSON;
    }

    my $short_content = $self->get('content');
    if ( length $short_content > $max_length ) {
        $short_content = substr( $short_content, 0, $max_length - 1 ) . '…';
    }

    return Cpanel::LocaleString->new(
        'The response to the [output,abbr,HTTP,Hypertext Transfer Protocol] “[_1]” request from “[_2]” indicated an error ([_3], [_4]): [_5]',
        $self->get('method'),
        $self->get_url_without_password(),
        $self->get('status'),
        $self->get('reason'),
        $short_content,
    );
}

sub method  { return shift()->get('method') }
sub content { return shift()->get('content') }
sub url     { return shift()->get('url') }
sub status  { return shift()->get('status') }
sub reason  { return shift()->get('reason') }
sub headers { return shift()->get('headers') }

1;
