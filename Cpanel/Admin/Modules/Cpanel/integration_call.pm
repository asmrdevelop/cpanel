
# cpanel - Cpanel/Admin/Modules/Cpanel/integration_call.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Admin::Modules::Cpanel::integration_call;

use strict;
use warnings;

use parent qw( Cpanel::Admin::Base );

use Cpanel::JSON                ();
use Cpanel::Exception           ();
use Cpanel::HTTP::Client        ();
use Cpanel::Integration::Config ();
use Cpanel::Integration         ();
use Cpanel::Logger              ();
use Cpanel::Locale              ();
use Try::Tiny;

my $locale;
my $logger;

=encoding utf-8

=head1 NAME

Cpanel::Admin::Modules::Cpanel::integration_call - And admin module to support integrated applications

=cut

# Do not add to this list
sub _actions__pass_exception {
    return (
        'FETCH_AUTO_LOGIN_URL',
    );
}

# Add to this list instead.
use constant _actions => (
    _actions__pass_exception(),
);

sub _demo_actions {
    return ();
}

=head2 FETCH_AUTO_LOGIN_URL()

Description:
  Call out to a url with a token to retrieve a json encoded hashref that contains
  a 'redirect_url' that will allow the user automatic login to a remote integrated system

Parameters:
  app       - The integrated app configuration to use

Returns:
  A hashref that represents the deserialized json strucutre
  returned from the auto login url

=cut

sub FETCH_AUTO_LOGIN_URL {
    my ( $self, $ref_hr ) = @_;

    foreach my $required (qw(app)) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $required ] ) if !$ref_hr->{$required};
    }

    my $caller_username = $self->get_caller_username();

    # These should never happen since the adminbin will not be
    # called if these are missing, however they are here as a sanity check.
    Cpanel::Integration::Config::get_app_config_path_for_user( $caller_username, $ref_hr->{'app'} )  or die "The user configuration is missing for the app “$ref_hr->{'app'}”";     # not configured
    Cpanel::Integration::Config::get_app_config_path_for_admin( $caller_username, $ref_hr->{'app'} ) or die "The admin configuration is missing for the app “$ref_hr->{'app'}”";    # not configured

    my $attempt             = 0;
    my $response_to_caller  = {};
    my $user_post_data      = Cpanel::Integration::load_user_app_config( $caller_username, $ref_hr->{'app'} );
    my $autologin_token_url = delete $user_post_data->{'autologin_token_url'};

    if ( !$autologin_token_url ) {

        # This error should never happen since the adminbin will not be called if it is not present.
        die "The link url is missing from user “$caller_username” app config for the application “$ref_hr->{'app'}”.";
    }
    $response_to_caller->{'url'} = $user_post_data->{'url'} if $user_post_data->{'url'};

    my $http_client = Cpanel::HTTP::Client->new();

  FETCH_ATTEMPT:
    while ( ++$attempt <= 3 ) {

        # Load every time because we may be told to retry because we are waiting for the new token
        my $admin_post_data = Cpanel::Integration::load_admin_app_config( $caller_username, $ref_hr->{'app'} );
        my $response        = $http_client->post_form(
            $autologin_token_url,
            {
                %$user_post_data,
                %$admin_post_data,
                'attempt' => $attempt,
            },
            {

                'headers' => { 'Content-type' => 'application/x-www-form-urlencoded' },
            }
        );
        if ( !$response->success() ) {
            my $msg = _locale()->maketext( "The system was unable to fetch a response from “[_1]” because of an error: [_2]", $autologin_token_url, "$response->{status} $response->{reason}" );
            _logger()->warn($msg);
            die $msg;
        }

        my $err;
        try {
            my $response_ref = Cpanel::JSON::Load( $response->content() );
            @{$response_to_caller}{ keys %$response_ref } = values %$response_ref;
        }
        catch {
            $err = $_;
        };

        if ($err) {
            my $msg = _locale()->maketext( "The system was unable to parse the response from “[_1]” because of an error: [_2]", $autologin_token_url, Cpanel::Exception::get_string($err) );

            _logger()->warn($msg);
            die $msg;
        }

        last FETCH_ATTEMPT if $response_to_caller->{'redirect_url'} || !$response_to_caller->{'retry'};

        # If the remote told us to retry in x seconds, sleep for that time
        if ( my $sleep = abs int $response_to_caller->{'retry'} ) {
            _logger()->info("The remote told us to retry in $sleep seconds while fetching the autologin_token_url for $caller_username");
            _sleep( $sleep > 60 ? 60 : $sleep );    # sleep a maximum of 60 seconds to wait for the token to be refreshed
        }
    }

    return $response_to_caller;

}

sub _logger {
    return ( $logger ||= Cpanel::Logger->new() );
}

sub _locale {
    return ( $locale ||= Cpanel::Locale->get_handle() );
}

sub _sleep {
    return sleep( $_[0] );
}

#----------------------------------------------------------------------

1;
