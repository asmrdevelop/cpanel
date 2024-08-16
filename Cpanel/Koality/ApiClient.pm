package Cpanel::Koality::ApiClient;

# cpanel - Cpanel/Koality/ApiClient.pm             Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Moo;
use cPstrict;
use Cpanel::Imports;
extends 'Cpanel::Plugins::RestApiClient';

use Cpanel::JSON          ();
use Cpanel::Rand::Get     ();
use Cpanel::Koality::Auth ();

=head1 MODULE

C<Cpanel::Koality::ApiClient>

=head1 DESCRIPTION

C<Cpanel::Koality::ApiClient> is a subclass of Cpanel::Plugins::RestApiClient
for use with Koality Site Quality Monitoring.

=head1 METHODS

=head2 new( cpanel_username )

Instantiate a C<Cpanel::Koality::ApiClient> object.

=head3 ARGUMENTS

=over

=item cpanel_username - string - Required

The user's cPanel username.

=back

=head3 RETURNS

A C<Cpanel::Koality::ApiClient> object.

=head3 EXAMPLES

my $api = Cpanel::Koality::ApiClient->new( cpanel_username => 'the_username' );

$api->method('GET');

$api->endpoint( "project/systems/id/systemType" );

$api->payload( { access_token => 'a_token' } );

my $response = $api->run();

=head2 reauth_handler()

Reauthenticates the Koality session and updates the authentication token used
by the C<Cpanel::Koality::ApiClient> object.

=head3 ARGUMENTS

None.

=head3 RETURNS

Returns 1.

=head3 EXAMPLES

my $api = Cpanel::Koality::ApiClient->new( cpanel_username => 'the_username' );

$api->reauth_handler();

=cut

has 'cpanel_username' => (
    is  => 'rw',
    isa => sub {
        require Cpanel::Validate::Username;
        Cpanel::Validate::Username::user_exists_or_die( $_[0] );
    },
    default => sub ($self) { return $Cpanel::user || die 'Must set the cpanel_username attribute.' }
);

=item * C<headers>

A Key/Value hashref of headers used during REST requests.

=cut

has '+headers' => (
    default => sub ($self) {
        my $auth = Cpanel::Koality::Auth->new( 'cpanel_username' => $self->cpanel_username );
        return {
            'Content-Type'    => 'application/json',
            'Accept-Language' => $auth->activation_email_locale,
        };
    },
);

sub reauth_handler ($self) {
    $Cpanel::user //= $self->cpanel_username;

    my $auth = Cpanel::Koality::Auth->new( 'cpanel_username' => $self->cpanel_username );

    # Only reauth to an api cluster endpoint.
    return 0 unless defined $self->base_url;
    return 0 if $self->base_url eq $auth->auth_url || $self->base_url eq $auth->app360_url;

    # disable trying to reauth our reauth.
    $auth->api->try_reauth('0');
    my $user = $auth->auth_session();

    $self->auth_token( $user->session_token );
    $self->payload->{access_token} = $user->session_token;

    return 1;
}

=head2 handle_error()

Used to report errors to the user and logs.

=head3 ARGUMENTS

This handler can consume three types of errors:

A C<Cpanel::HTTP::Client::Response> object

A C<Cpanel::Exception::HTTP::Network> object

A string.

Anything else will produce a generic error message in the cpanel error log.

=head3 RETURNS

Always dies with a generic error message.

=cut

sub handle_error ( $self, $response_obj ) {

    my $id = _get_rand_id();

    if ( $response_obj->isa('Cpanel::HTTP::Client::Response') ) {

        my $err_str = "[$id] The Site Quality Monitoring request to " . $response_obj->url() . " returned a " . $response_obj->status() . " status: " . $response_obj->reason();

        my $content = eval { Cpanel::JSON::Load( $response_obj->content() ) };
        if ( $content && $content->{'error'} ) {
            my $err_msg = $content->{'error'};
            $err_str = $err_str . ": $err_msg";
            if ( $err_msg eq 'User already exists.' ) {
                logger()->error($err_str);
                die "[$id] " . locale->maketext("Failed to create a new Site Quality Monitoring user. Check that you have not already signed up with this email address.") . "\n";
            }
        }

        logger()->error($err_str);
    }
    elsif ( $response_obj->isa('Cpanel::Exception::HTTP::Network') ) {
        logger()->error( "[$id] The Site Quality Monitoring request to " . $response_obj->get_url_without_password() . " failed: " . $response_obj->get('error') );
    }
    elsif ( !ref($response_obj) && length $response_obj ) {
        logger()->error("[$id] A Site Quality Monitoring remote request failed: $response_obj");
    }
    else {
        logger()->error("[$id] A Site Quality Monitoring remote request failed.");
    }

    _die_with_generic_message($id);
    return 1;
}

=head2 handle_success()

Used to parse and return a successful response to the caller.

=head3 ARGUMENTS

This handler can consume only C<Cpanel::HTTP::Client::Response> objects.

=head3 RETURNS

Returns a hash of the response's content if given a C<Cpanel::HTTP::Client::Response> object.

Otherwise returns 1.

=cut

sub handle_success ( $self, $response_obj ) {

    if ( $response_obj->isa('Cpanel::HTTP::Client::Response') ) {

        my $content = $response_obj->content();

        if ($content) {
            local $@;
            my $json_response = eval { Cpanel::JSON::Load($content) };
            if ( my $exception = $@ ) {
                my $id = _get_rand_id();
                logger()->error("[$id] A request to the Site Quality Monitoring service returned an invalid response: $exception");
                _die_with_generic_message($id);
            }
            return $json_response;
        }
    }

    return 1;
}

sub _die_with_generic_message ($id) {
    die "[$id] " . locale()->maketext("The Site Quality Monitoring service is experiencing technical difficulties. Try again later.") . "\n";
    return 1;
}

sub _get_rand_id {
    return Cpanel::Rand::Get::getranddata( 6, [ 0 .. 9, 'a' .. 'z' ] );
}

1;
