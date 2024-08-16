
# cpanel - Cpanel/DAV/Result.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::DAV::Result;

use strict;
use Cpanel::DAV::Result::Meta ();
use Cpanel::Locale::Lazy 'lh';

use Carp ();
use Class::Accessor 'antlers';    # lightweight Moose-style attributes

=head1 NAME

Cpanel::DAV::Result

=head1 CONSTRUCTION

Builds an initialized result object

=cut

sub new {
    my ($class) = @_;
    my $self = {
        data => undef,
        meta => Cpanel::DAV::Result::Meta->new(),
    };
    bless $self, $class;
    return $self;
}

=head1 ATTRIBUTES

The attributes of a result are accessible by getter/setter methods
of the same name as the attribute.

=head2 data

Data returned by a call to DAV subsystem.

=cut

has data => ( is => 'rw' );

=head2 meta

Meta data returned by a call to DAV subsystem. Meta data includes information about the success
or exceptional failure of the call not normally contained in the calls regular response.

=cut

has meta => ( is => 'rw', isa => 'Cpanel::DAV::Result::Meta' );

=head2 uri

If provided, this is the URI that was hit by the HTTP query that produced the result.

=cut

has uri => ( is => 'rw' );

=head2 request

If provided, this in an HTTP::Request object representing the operation that was
performed/attempted to produce this result.

=cut

has request => ( is => 'rw', isa => 'HTTP::Request' );

=head1 FUNCTIONS

=head2 success

Helper method to initialize a successful result object.

Arguments

  $status - number - HTTP Status code, if applicable.
  $text   - string - Application specific message related to action.
  $data   - any    - Optional, data returned by the request, usually the object being added or modified
.

=cut

sub success {
    my ( $self, $status, $text, $data ) = @_;
    $self->data($data);
    $self->meta->ok(1);
    $self->meta->text($text);
    $self->meta->status($status);
    return $self;
}

=head2 failed

Helper method to initialize a failed result object.

Arguments

  $status  - number - HTTP Status code, if applicable.
  $text    - string - Application specific message related to action.
  $details - any    - Optional, details of the failure, usually an object, exception or collection of either.

=cut

sub failed {
    my ( $self, $status, $text, $details ) = @_;
    $self->data(undef);
    $self->meta->ok(0);
    $self->meta->status($status);
    $self->meta->text($text);
    $self->meta->details($details);
    return $self;
}

=head2 conditional

Helper method to initialize a result object based on a boolean
success or failure status and the messages for each. This is expected
to be used for non-HTTP operations, so HTTP-related information is
not inserted into the object.

Arguments

  $ok           - boolean - True if the the operation succeeded; otherwise false.
  $success_text - string  - The text to use in case of success.
  $error_text   - string  - The text to use in case of error.
  $data         - any     - Optional, data returned by the request, usually the object being added or modified

=cut

sub conditional {
    my ( $self, $ok, $success_text, $error_text, $data ) = @_;
    $self->data($data);
    $self->meta->ok($ok);
    $self->meta->text( $ok ? $success_text : $error_text );
    return $self;
}

=head2 exception

Helper method to initialize an exception based failure result object.

Arguments

  $text      - string - Application specific message related to action.
  $exception - any    -    Optional, exception or collection of exceptions.

=cut

sub exception {
    my ( $self, $text, $exception ) = @_;
    $self->data(undef);
    $self->meta->ok(0);
    $self->meta->is_exception(1);
    $self->meta->text($text);
    $self->meta->details($exception);
    return $self;
}

=head2 no_response

Helper method to initialize result object when the request didn't respond.

Arguments

  $text - string - Application specific message related to action.

=cut

sub no_response {
    my ( $self, $text ) = @_;
    $self->data(undef);
    $self->meta->ok(0);
    $self->meta->no_response(1);
    $self->meta->text($text);
    return $self;
}

=head2 as_string

Returns a single string that includes the most important information from
the result, including:

  - Whether the operation succeeded or failed
  - The HTTP status (numeric and/or text)
  - The exception detail from the application, if applicable

This is suitable for use as an error message in the case of a failure.

=cut

sub as_string {
    my ($self) = @_;

    my $detail_message;
    if ( 'HASH' eq ref $self->meta->details ) {
        for my $detail_item ( keys %{ $self->meta->details } ) {
            if ( $detail_item =~ /^[^:]+:message$/ ) {    # looking for s:message from Sabre without caring about exact namespace
                $detail_message = $self->meta->details->{$detail_item};
                last;
            }
        }
    }

    my ( $method, $uri );
    if ( $self->request ) {
        $method = $self->request->method;
        $uri    = $self->request->uri;
    }
    else {
        $method = $ENV{REQUEST_METHOD} || 'UNKNOWN';
        $uri    = $self->uri || $ENV{REQUEST_URI} || 'UNKNOWN';
    }

    if ( $self->meta->ok ) {
        return lh()->maketext( 'The operation “[_1]” “[_2]” succeeded.', $method, $uri );
    }
    else {
        if ($detail_message) {
            return lh()->maketext( 'The operation “[_1]” “[_2]” failed with a “[_3]” error: [_4]', $method, $uri, $self->meta->text, $detail_message );
        }
        return lh()->maketext( 'The operation “[_1]” “[_2]” failed with a “[_3]” error.', $method, $uri, $self->meta->text );
    }
}

sub TO_JSON {
    return { %{ $_[0] } };
}

1;
