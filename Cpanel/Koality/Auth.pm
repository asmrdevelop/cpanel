package Cpanel::Koality::Auth;

# cpanel - Cpanel/Koality/Auth.pm                  Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Moo;
use cPstrict;
use Cpanel::Imports;

extends 'Cpanel::Koality::Base';

use Cpanel::Koality::User     ();
use Cpanel::Koality::Validate ();
use Cpanel::JSON              ();
use Cpanel::Rand::Get         ();

=head1 MODULE

C<Cpanel::Koality::Auth>

=head1 DESCRIPTION

C<Cpanel::Koality::Auth> is a class that provides methods for tasks relating to creating or authenticating a Koality user.

=cut

=head2 activation_email_locale - string

The locale of the activation email sent during new user sign up.

=cut

has 'activation_email_locale' => (
    is      => 'rw',
    isa     => \&Cpanel::Koality::Validate::valid_activation_email_locale,
    default => sub ($self) {
        require Cpanel::Locale::Utils::User;
        my $locale = Cpanel::Locale::Utils::User::get_user_locale( $self->cpanel_username );
        return 'en' if !$locale;

        $locale = substr $locale, 0, 2;
        return $locale;
    },
);

sub _get_app_token ($self) {
    my $user = Cpanel::Koality::User->new( cpanel_username => $self->cpanel_username, );

    return $user->app_token;
}

=head1 METHODS

=head2 create_user( username, password )

Create a new Koality user and associate it with a cPanel account.

=head3 ARGUMENTS

=over

=item username - string - Required

The email to associate with the Koality account/user.

=item password - string

A password for authentication. If one is not provided, a pseudorandom one is generated.

=back

=head3 RETURNS

An instance of C<Cpanel::Koality::User> created using the provided details as well as the newly acquired app token.

=head3 EXAMPLES

my $auth = Cpanel::Koality::Auth->new();

my $user = eval { $auth->create_user( $email, $pass ) };

=cut

sub create_user ( $self, $username, $password = '' ) {
    if ( $self->_get_app_token() ) {
        die locale()->maketext("This cPanel user already has an associated Site Quality Monitoring account.") . "\n";
    }

    $password ||= Cpanel::Rand::Get::getranddata( 64, [ 0 .. 9, 'a' .. 'z', 'A' .. 'Z', '$', '%', '+', '!', '^', '*' ] );

    $self->api->base_url( $self->app360_url );
    $self->api->method('POST');
    $self->api->endpoint('user/create');
    $self->api->payload(
        {
            email             => $username,
            consent           => Cpanel::JSON::true(),
            password          => $password,
            createToken       => Cpanel::JSON::true(),
            preferredLanguage => $self->activation_email_locale,

            # For analytics and consent identification
            companyId => $self->company_id,
            serverId  => $self->server_id,
            userId    => $self->cpanel_username,

            # For linking users to stripe accounts.
            uuid => $self->uuid,
        }
    );

    my $response = $self->api->run();

    my $user = Cpanel::Koality::User->new(
        koality_username => $username,
        cpanel_username  => $self->cpanel_username,
        app_token        => $response->{token},
    );
    $user->save_user_info();

    return $user;
}

=head2 auth_session()

Generate an authenticated session for the Koality user associated with the current cPanel account.

=head3 ARGUMENTS

=over

=item None.

=back

=head3 RETURNS

An instance of C<Cpanel::Koality::User> authenticated using the details saved during user creation.

=head3 EXAMPLES

my $auth = Cpanel::Koality::Auth->new();

my $user = eval { $auth->auth_session() };

=cut

sub auth_session ($self) {

    my $user = $self->get_user();
    $self->get_session_tokens($user);
    $user->disable_onboarding();

    return $user;
}

=head2 get_user()

Retrieves a users information from the koality backend.

=head3 ARGUMENTS

=over

=item None.

=back

=head3 RETURNS

An instance of C<Cpanel::Koality::User> authenticated using the details saved during user creation.

=cut

sub get_user ($self) {

    $self->api->base_url( $self->auth_url );
    $self->api->method('POST');
    $self->api->endpoint('auth/session');

    my $token = $self->_get_app_token() // die locale()->maketext( "No token found for user [_1].", $self->cpanel_username ) . "\n";
    $self->api->payload( { sessionToken => $token } );
    my $response = $self->api->run();

    my %user_info = (
        app_token        => $token,
        koality_username => $response->{data}{user}{email},
        auth_token       => $response->{data}{token},
        cluster_endpoint => $response->{data}{companies}[0]{cluster}{apiEndpoint} . "v1/",
        master_user_id   => $response->{data}{user}{id},
        enabled          => $response->{data}{user}{enabled},
        uuid             => $response->{data}{user}{userName},
    );

    my $user = Cpanel::Koality::User->new( cpanel_username => $self->cpanel_username, %user_info );
    $user->save_user_info();

    return $user;
}

=head2 get_session_tokens()

Retrieves a users session related information from the koality backend. The information is
updated in passed in C<Cpanel::Koality::User> properties and persisted to the file system.

=head3 ARGUMENTS

=over

=item None.

=back

=head3 RETURNS

An instance of C<Cpanel::Koality::User> authenticated using the details saved during user creation.

=cut

sub get_session_tokens ( $self, $user ) {

    my $url        = $user->cluster_endpoint // die locale()->maketext( "No [_1] found. You must authenticate first.", "Site Quality Monitoring server" );
    my $id         = $user->master_user_id   // die locale()->maketext( "No [_1] found. You must authenticate first.", "Site Quality Monitoring user ID" );
    my $auth_token = $user->auth_token       // die locale()->maketext( "No [_1] found. You must authenticate first.", "Site Quality Monitoring API authentication token" );

    $self->api->method('POST');
    $self->api->base_url($url);
    $self->api->endpoint( "auth/tokens/token/" . $id );
    $self->api->auth_token($auth_token);
    $self->api->payload( { access_token => $auth_token } );
    my $response = $self->api->run();

    $user->session_token( $response->{data}{token} );
    $user->refresh_token( $response->{data}{refresh_token} );
    $user->user_id( $response->{data}{user}{id} );

    $user->save_user_info( $response->{data} );

    return $user;
}

=head2 verify_code()

Verifies a code that was sent to the user via email.

=head3 ARGUMENTS

=over

=item code - String - Required

The string to verify.

=back

=head3 RETURNS

Whether or not the code was verified successfully.

=over

=item status - bool

Returns 1 when the code is verified.

Returns 0 when the code fails to verify.

=back

=head3 EXAMPLES

my $auth = Cpanel::Koality::Auth->new();

$auth->verify_code('1234');

=cut

sub verify_code ( $self, $code ) {

    my $user = $self->get_user();

    $self->api->base_url( $user->auth_url );
    $self->api->method('POST');
    $self->api->endpoint('user/activate/code');
    $self->api->payload(
        {
            activation_code => $code,
            user            => $user->master_user_id
        }
    );

    my $response = $self->api->run();

    return defined $response->{status} && $response->{status} eq 'success' ? 1 : 0;
}

=head2 delete_user()

Delete the user associated with the current cPanel account, and reset the configuration file.

=head3 ARGUMENTS

None.

=head3 RETURNS

Whether or not the request to delete the user was successful.

=over

=item status - bool

Returns 1 when the user deletion was successful.

Returns 0 when the user deletion was not successful.

=back

=head3 EXAMPLES

my $auth = Cpanel::Koality::Auth->new();

$auth->delete_user();

=cut

sub delete_user ($self) {

    my $remote_account_deleted = 0;

    # If get_user() fails, we may have a stale/invalid account. Use a dummy user instead.
    my $user = eval { $self->get_user() };
    if ( my $exception = $@ ) {
        logger()->error($exception);
        $user = Cpanel::Koality::User->new( cpanel_username => $self->cpanel_username );
    }

    # If the user's config file does not exist, there's nothing we can do.
    if ( !-e $user->_conf_file ) {
        die locale()->maketext( 'The system did not find a Site Quality Monitoring configuration file for user [_1].', $self->cpanel_username ) . "\n";
    }

    # If the user does not have an $auth_token we can not even attempt to delete the account.
    my $auth_token = $user->auth_token;
    if ($auth_token) {

        # Try to delete the account from the auth system
        $self->api->base_url( $user->auth_url );
        $self->api->method('DELETE');
        $self->api->endpoint( 'user/' . $user->master_user_id );
        $self->api->payload( { access_token => $auth_token } );

        my $response = eval { $self->api->run() };
        if ( my $exception = $@ ) {
            logger()->error($exception);
        }
        else {
            $remote_account_deleted = ( defined $response->{status} && $response->{status} eq 'success' ) ? 1 : 0;
        }
    }

    # Always reset the local config even when the
    # account does not have a valid $auth_token.
    $user->reset_config();

    return $remote_account_deleted;
}

=head2 send_activation_email()

Triggers the send of a new user activation email.

=head3 ARGUMENTS

None.

=head3 RETURNS

Whether or not the request to send the email was successful.

=over

=item status - bool

Returns 1 when the email request was successful.

Returns 0 when the email request was not successful.

=back

=head3 EXAMPLES

my $auth = Cpanel::Koality::Auth->new();

$auth->send_activation_email();

=cut

sub send_activation_email ($self) {

    my $user = $self->get_user();

    $self->api->base_url( $user->auth_url );
    $self->api->method('POST');
    $self->api->endpoint('user/resend-activation');
    $self->api->payload( { user => $user->master_user_id } );

    my $response = $self->api->run();

    return defined $response->{status} && $response->{status} eq 'success' ? 1 : 0;
}

1;
