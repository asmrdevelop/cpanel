package Cpanel::Plugins::RestApiClient;

# cpanel - Cpanel/Plugins/RestApiClient.pm         Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Moo;
use cPstrict;

use Cpanel::HTTP::Client ();
use Cpanel::JSON         ();
use Cpanel::Exception    ();

=head1 MODULE

=head2 NAME

Cpanel::Plugins::RestApiClient

=head2 DESCRIPTION

The purpose of this class is to communicate with a REST API server.

=head2 SYNOPSIS

    my $api = Cpanel::Plugins::RestApiClient->new();

    $api->base_url('https://my.restapi.com/v1/');
    $api->endpoint('users');
    my $response = $api->run();

    $api->endpoint('projects');
    $response = $api->run();

=head2 ATTRIBUTES

=over

=item * C<http_client>

The Cpanel::HTTP::Client object. This object facilitates the communication with the remote REST API.

=cut

has http_client => (
    is      => 'ro',
    default => sub ($self) {
        return Cpanel::HTTP::Client->new( timeout => $self->timeout )->return_on_http_error();
    },
    lazy => 1,
);

=item * C<timeout>

The timeout for requests.

NOTE: 'timeout' is a read-only attribute that should only be set in the object constructor.
Changing the timeout attribute between rest api calls can lead to unintended behavior as the
new HTTP client will create a new socket which is immediately ready for r/w operations and thus
will not properly time out when expected.

=cut

has timeout => (
    is      => 'ro',
    default => 10,
);

=item * C<payload>

A Key/Value hash that contains the content of the REST API request.

=cut

has 'payload' => (
    is => 'rw',
);

=item * C<base_url>

The common URL used by all REST API requests.

This should include the full protocol, "https://...."

=cut

has 'base_url' => (
    is => 'rw',
);

=item * C<endpoint>

The endpoint of the REST API request. This is appended to the "base_url".

=cut

has 'endpoint' => (
    is => 'rw',
);

=item * C<headers>

A Key/Value hashref of headers used during REST requests.

Defaults to "Content-Type -> application/json"

=cut

has 'headers' => (
    is      => 'rw',
    isa => sub {
        die 'Not a Hashref.' if ref( $_[0] ) ne 'HASH';
    },
    default => sub {
        return { 'Content-Type' => 'application/json' };
    },
);

=item * C<method>

The HTTP method to use for the REST request. Defaults to 'GET'.

=cut

has 'method' => (
    is      => 'rw',
    default => 'GET',
);

=item * C<auth_token>

The authentication token to use for the REST request.

If this is set, it will be added to the headers as a Authorization/Bearer token.

=cut

has 'auth_token' => (
    is => 'rw',
);

=item * C<retry>

The number of times to retry a REST request that fails due to network errors.

=cut

has 'retry' => (
    is      => 'rw',
    default => '5',
);

=item * C<try_reauth>

Whether or not the current api call should try to reauth on a 401 failure.

=cut

has 'try_reauth' => (
    is      => 'rw',
    default => '1',
);

=item * C<required_attrs>

The attributes that must be defined to run a REST request.

=cut

has 'required_attrs' => (
    is      => 'ro',
    default => sub { return qw( base_url endpoint ) },
);

=back

=cut

=head2 METHODS

=over

=item * C<run>

Executes a REST request based on the values of the attributes.

On a network failure the request will be repeated up to the 'retry' attribute value.

Must have the "required_attrs" set.

On success, returns the content of the request.

On failure, returns a HTTP::Server exception.

=back

=cut

sub run ($self) {

    for ( $self->required_attrs ) {
        die "You must define the \'$_\' attribute." if !$self->$_;
    }

    my $headers = $self->headers;

    $headers->{'Authorization'} = 'Bearer ' . $self->auth_token if $self->auth_token;

    my $response_obj;

    for ( 1 .. $self->retry ) {
        local $@;
        eval {
            $response_obj = $self->http_client->request(
                $self->{method},
                $self->{base_url} . $self->{endpoint},
                {
                    'headers' => $headers,
                    'content' => Cpanel::JSON::Dump( $self->{payload} ),
                }
            );
        };
        if ( my $exception = $@ ) {
            $self->handle_error($exception);
        }

        if ( grep { $_ eq $response_obj->status() } _network_status_codes() ) {
            next;    # retry on network error/timeout
        }
        elsif ($response_obj->status() eq '401'
            && $self->can('reauth_handler')
            && $self->try_reauth ) {

            # if we are unathorized, provide a way to reauthorize and try again.
            my $try_again = $self->reauth_handler();
            $try_again ? next : last;
        }
        else {
            last;
        }
    }

    return $response_obj->success() ? $self->handle_success($response_obj) : $self->handle_error($response_obj);

}

=over

=item * C<handle_success>

Handler for when the API request returns a successful status.

If there is no content, we return '1', otherwise return the raw content.

Subclass if you need additional behavior.

=back

=cut

sub handle_success ( $self, $response_obj ) {
    return $response_obj->content() ? $response_obj->content() : 1;
}

=over

=item * C<handle_error>

Handler for when the API request returns a unsuccessful response.

Throws a Cpanel::Exception::HTTP::Server exception.

Subclass if you need additional behavior.

=back

=cut

sub handle_error ( $self, $response_obj ) {
    return _throw_error($response_obj);
}

=over

=item * C<handle_timeout>

Handler for when the API request returns a timeout status.

Throws a Cpanel::Exception::HTTP::Server exception.

Subclass if you need additional behavior.

=back

=cut

sub _throw_error ($resp_obj) {

    if ( $resp_obj->isa('Cpanel::HTTP::Client::Response') ) {
        die Cpanel::Exception::create(
            'HTTP::Server',
            [
                content_type => scalar( $resp_obj->header('Content-Type') ),
                ( map { ( $_ => $resp_obj->$_() ) } qw( content status reason url headers redirects ) ),
            ],
        );
    }

    die $resp_obj . "\n" if length $resp_obj;

    return 1;
}

sub _network_status_codes {
    return (
        '408',    # Request Timeout
        '503',    # Service Unavailable
        '504',    # Gateway Timeout
        '524',    # A Timeout Occurred
        '598',    # Network read timeout error
        '599',    # Network Connect Timeout Error
    );
}

1;
