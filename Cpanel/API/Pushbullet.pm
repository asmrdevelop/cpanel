package Cpanel::API::Pushbullet;

# cpanel - Cpanel/API/Pushbullet.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# CPANEL-2113: Do not import try/catch/finally
# into our namespace
use Try::Tiny ();

use Cpanel::Locale                ();
use Cpanel::Pushbullet            ();
use Cpanel::Exception             ();
use Cpanel::iContact::TestMessage ();

=head1 NAME

Cpanel::API::Pushbullet

=head1 DESCRIPTION

UAPI functions related to Pushbullet.

=head2 send_test_message

=head3 Purpose

Sends a test message using a provided token to determine if the token is valid, and the account holder can receive the message.

=head3 Arguments

  access_token - the Pushbullet access_token to send the test message to.

=head3 Returns

  message_id - The message_id associated with the Cpanel::iContact::TestMessage that was sent.
  payload - Returns the Pushbullet response object. see https://docs.pushbullet.com#pushes for more information.

=cut

sub send_test_message {
    my ( $args, $result ) = @_;

    my ($user) = $Cpanel::authuser;
    my $locale = _locale();
    my $token  = $args->get('access_token');

    my $domain;
    if ( $user =~ m/@/ ) {
        $domain = ( split '@', $user )[1];
    }
    else {
        $domain = $Cpanel::CPDATA{'DOMAIN'};
    }

    if ( !$token ) {
        die Cpanel::Exception->create( "You must supply a valid access token. If you do not have an access token, you can obtain one from [_1].", ['https://www.pushbullet.com/'] );
    }

    my $pb           = Cpanel::Pushbullet->new( access_token => $token );
    my $body         = $locale->maketext( "This message confirms that “[_1]” can send a message to you via [asis,Pushbullet].", $domain );
    my $test_message = Cpanel::iContact::TestMessage->new($body);

    # This will throw an exception if it fails internally.
    my $payload = $pb->push_note(
        title => $test_message->get_subject(),
        body  => $test_message->get_body_with_timestamp(),
    );

    # Assumes no exception was thrown by push_note
    $result->data( { 'message_id' => $test_message->get_message_id(), 'payload' => $payload } );
    return 1;
}

my $_locale;

sub _locale {
    return $_locale ||= Cpanel::Locale->get_handle();
}

our %API = (
    send_test_message => { allow_demo => 1 },
);

1;
