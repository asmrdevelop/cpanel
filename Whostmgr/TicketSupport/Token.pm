package Whostmgr::TicketSupport::Token;

# cpanel - Whostmgr/TicketSupport/Token.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Debug            ();
use Cpanel::Exception        ();
use Cpanel::Session::Restore ();
use Whostmgr::TicketSupport  ();

sub new {
    my $class = shift;

    my ( $session_id, $session_data ) = Cpanel::Session::Restore::restoreSession();

    if ( !$session_id ) {
        die Cpanel::Exception->create('The system failed to restore the saved session.');
    }

    my $self = {
        session => {
            id   => $session_id,
            data => $session_data || {},
        }
    };

    bless $self, $class;
    return $self;
}

=head1 NAME

Whostmgr::TicketSupport::Token

=head2 value()

This instance method returns the value of the OAuth2 token if it exists or undef it doesn't.

=head3 Arguments

=over

=item B<NONE>

=back

=head3 Returns

=over

=item B<TOKEN> (string)

=over

=item The OAuth2 token that is attached to the current session, if it exists. It will be undef otherwise.

=back

=back

=cut

sub value {
    my $self = shift;
    return $self->{session}{data}{cp_ticket_system_token} if $self->is_present();
    return;
}

=head2 fetch(ARGS)

This instance method takes an OAuth2 code returned from the ticket system and attempts to retrieve the actual token that can be used for API calls. The token is returned and stored on the current session.

=head3 Arguments

=over

=item B<ARGS> (hash ref)

=over

=item B<code> (string)

=over

=item The code received from the OAuth2 redirect. It will be validated and exchanged for a token.

=back

=item B<redirect_uri> (string)

=over

=item The same redirect_uri query argument that was passed to the initial OAuth2 authentication endpoint.

=back

=back

=back

=head3 Returns

=over

=item B<TOKEN> (string)

=over

=item The OAuth2 token that is received in exchange for the code. This is the token that is used to authenticate future OAuth2 requests.

=back

=back

=cut

sub fetch {
    my ( $self, $args ) = @_;

    if ( !defined $args->{code} || !defined $args->{redirect_uri} ) {
        die Cpanel::Exception->create('The request must include the [asis,OAuth2] code and associated redirect [asis,URI] arguments to retrieve the token.');
    }

    my ( $session_id, $session_data ) = ( $self->{session}{id}, $self->{session}{data} );
    require Cpanel::OAuth2;
    my ( $response, $status ) = Cpanel::OAuth2::validate_code(
        $args->{code},
        {
            redirect_uri => $args->{redirect_uri},
        }
    );

    # Check to make sure everything's in order
    if ( $status == 200 && ref $response eq 'HASH' && $response->{access_token} ) {

        # The code is valid, so update the token in the session data.
        $session_data->{cp_ticket_system_token}            = $response->{access_token};
        $session_data->{cp_ticket_system_refresh_token}    = $response->{refresh_token};
        $session_data->{cp_ticket_system_token_expires_in} = $response->{expires_in};

        # TODO: Use Cpanel::Session::Modify
        require Cpanel::Session;
        Cpanel::Session::saveSession( $session_id, $session_data );

        return $response->{access_token};
    }
    else {

        if ( !$status ) {
            _log_error( $status, $response );
            die Cpanel::Exception::create( 'TicketSupport::OAuth2::Connection', 'The server was unable to contact the [asis,cPanel] Customer Portal.' );
        }
        elsif ( $status != 200 ) {

            # There was something wrong with the code. The token for our client_id is bad now
            # too, so delete any token that existed previously.
            if ( defined $session_data->{cp_ticket_system_token} ) {
                delete $session_data->{cp_ticket_system_token};
                require Cpanel::Session;

                # TODO: Use Cpanel::Session::Modify
                Cpanel::Session::saveSession( $session_id, $session_data );
            }

            _log_error( $status, $response );
            die Cpanel::Exception::create( 'TicketSupport::OAuth2::Status', 'The server failed to retrieve an access token from the [asis,cPanel] Customer Portal. Status Code: [_1]', [$status], { status => $status } );
        }
        else {
            _log_error( $status, $response );
            die Cpanel::Exception::create( 'TicketSupport::OAuth2::Response', 'The server received a malformed response from the [asis,cPanel] Customer Portal.' );
        }
    }
}

=head2 is_present()

This instance method is used to determine if a token is attached to the current session or not.

=head3 Arguments

=over

=item B<NONE>

=back

=head3 Returns

=over

=item B<IS_PRESENT> (boolean)

=over

=item True (1) if the OAuth2 token is present in the current session data. False (0) otherwise.

=back

=back

=cut

sub is_present {
    my $self = shift;
    return ( defined $self->{session}{data} && defined $self->{session}{data}{cp_ticket_system_token} ) ? 1 : 0;
}

=head2 is_valid()

This instance method tests the current OAuth2 token against a basic endpoint on the ticket system to see if the token is valid.

=head3 Arguments

=over

=item B<NONE>

=back

=head3 Returns

=over

=item B<IS_VALID> (boolean)

=over

=item True (1) if the OAuth2 token is valid. False (0) otherwise.

=back

=back

=cut

sub is_valid {
    my $self = shift;
    my ( $response, $status );

    eval { ( $response, $status ) = Whostmgr::TicketSupport::_do_basic_api_call( 'API_verify', 'V1', undef, 'HASH' ); };

    if ( $@ || $status != 200 || $response->{'status'} != 200 ) {
        _log_error( $response->{'status'}, $response->{'data'} );
        return 0;
    }
    else {
        return 1;
    }
}

=head2 delete()

This instance method removes the current OAuth2 token from the session data.

=head3 Arguments

=over

=item B<NONE>

=back

=head3 Returns

=over

=item B<NONE>

=back

=cut

sub delete {
    my $self = shift;
    if ( $self->{session}{data}{cp_ticket_system_token} ) {
        delete $self->{session}{data}{cp_ticket_system_token};
        require Cpanel::Session;
        Cpanel::Session::saveSession( $self->{session}{id}, $self->{session}{data} );
    }
    return;
}

=head2 set(TOKEN)

This instance method sets the ticket system token in the current session to the provided value in TOKEN.

=head3 Arguments

=over

=item B<TOKEN> (string)

=over

=item The value to store in cp_ticket_system_token in the session.

=back

=back

=head3 Returns

=over

=item B<NONE>

=back

=cut

sub set {
    my ( $self, $token ) = @_;

    if ( !$token ) {
        require Carp;
        Carp::croak('You must provide a token when calling the set method.');
    }

    $self->{session}{data}{cp_ticket_system_token} = $token;
    require Cpanel::Session;
    Cpanel::Session::saveSession( $self->{session}{id}, $self->{session}{data} );

    return;
}

sub _log_error {
    my ( $status, $data ) = @_;
    my $ref = defined $data ? ref $data : 'undef';
    $status //= 'undef';
    Cpanel::Debug::log_warn("No response, or an invalid one, came back from the cPanel Customer Portal. STATUS=$status REF=$ref");
    return;
}

1;
