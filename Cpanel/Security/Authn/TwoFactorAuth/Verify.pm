package Cpanel::Security::Authn::TwoFactorAuth::Verify;

# cpanel - Cpanel/Security/Authn/TwoFactorAuth/Verify.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::Hulk                   ();
use Cpanel::Hulk                           ();
use Cpanel::Logger                         ();
use Cpanel::Security::Authn::TwoFactorAuth ();
use Cpanel::Session                        ();
use Cpanel::Session::Load                  ();
use Cpanel::Session::Modify                ();

=head1 NAME

Cpanel::Security::Authn::TwoFactorAuth::Verify - 2FA token verifier with hulk/session integration.

=head1 SYNOPSIS

 use Cpanel::Security::Authn::TwoFactorAuth::Verify;

 if ( Cpanel::Security::Authn::TwoFactorAuth::Verify::verify_token_for_user($user, $formref->{tfa_token}, $current_session_id ) ) {
     print "2FA authentication passed.\n";
 }
 else {
     print "2FA authentication failed.\n";
 }

=head1 FUNCTIONS

=head2 C<verify_token_for_user($user, $token, $session_id)>

=head3 Arguments

=over 4

=item C<$user>

Required. The username the 2FA a token belongs to.

=item $token

Required. The 2FA token to check.

=item $sesion_id

Optional. The user's current cpsrvd session ID.

If supplied and valid for the user, a failed 2FA validation attempt will trigger a cphulk falure,
while a successful 2FA valiation attempt will update the session's "tfa_verified" field.

If the session contains a masquerading login, the C<$session{origin}{possessor}> field in the session
file must match the $user field supplied to the C<verify_token_for_user()> function to be valid.

For normal logins, the C<$session{user}> field must match.

=back

=head3 Returns

1 or 0 if the account is enabled for 2FA and a result was determined.

-1 if 2FA is not enabled for the account or verification of the token was not possible.

=head3 Throws

No exceptions are thrown from this function.

Any untrapped exceptions thrown by the modules it relies on are logged and discarded.

=cut

sub verify_token_for_user {
    my ( $user, $token, $session_id ) = @_;
    $user = $ENV{'TEAM_USER'} ? "$ENV{'TEAM_USER'}\@$ENV{'TEAM_OWNER'}" : $user;

    my $tfa_result = -1;
    my $tfa_obj;

    eval {
        # The token is considered valid if 2FA is not configured or the supplied token passes validation
        if (   Cpanel::Security::Authn::TwoFactorAuth::is_enabled()
            && ( $tfa_obj = Cpanel::Security::Authn::TwoFactorAuth->new( { 'user' => $user } ) )
            && $tfa_obj->is_tfa_configured() ) {

            $tfa_result = $tfa_obj->verify_token($token) ? 1 : 0;
        }
        my $session_user = $ENV{'TEAM_USER'} ? $ENV{'TEAM_USER'} . '@' . $ENV{'TEAM_LOGIN_DOMAIN'} : $user;

        if ($tfa_result) {
            _set_tfa_verified_in_session( $session_user, $token, $session_id );
        }
        else {
            _notify_hulk_failure( $session_user, $token, $session_id );
        }
    };
    if ($@) {
        Cpanel::Logger->new()->warn("Exception thrown during twofactorauth verification for $user: $@");
    }

    return $tfa_result;
}

sub _set_tfa_verified_in_session {
    my ( $username, $token, $session_id ) = @_;

    return unless length($session_id);

    my $session_obj = eval { Cpanel::Session::Modify->new( $session_id, 1 ) };

    return unless $session_obj;

    my $session_data = $session_obj->get_data();

    if ( _valid_session_data( $username, $session_data ) ) {
        $session_obj->set( 'tfa_verified', 1 );
        $session_obj->save();
    }
    else {
        $session_obj->abort();
    }

    return;
}

sub _notify_hulk_failure {
    my ( $username, $token, $session_id ) = @_;

    return unless length($session_id);

    my $session_data = Cpanel::Session::Load::loadSession($session_id);
    Cpanel::Session::decode_origin($session_data);

    my $cphulk;

    if (   _valid_session_data( $username, $session_data )
        && Cpanel::Config::Hulk::is_enabled()
        && ( $cphulk = Cpanel::Hulk->new() )
        && $cphulk->connect()
        && $cphulk->register( $session_data->{'origin'}{'app'} ) ) {

        my $ok_to_login = $cphulk->can_login(

            'user'         => $username,
            'remote_ip'    => $session_data->{'ip_address'},
            'local_ip'     => $session_data->{'local_ip_address'},
            'remote_port'  => $session_data->{'port'},
            'local_port'   => $session_data->{'local_port'},
            'service'      => $session_data->{'origin'}{'app'},
            'auth_service' => 'system',                              # webmail 2fa support is not implemented
            'authtoken'    => "2fa:$token",
            'status'       => 0,
            'deregister'   => 1,
        );

        if ( $ok_to_login == Cpanel::Hulk::HULK_ERROR() || $ok_to_login == Cpanel::Hulk::HULK_FAILED() ) {
            Cpanel::Logger->new()->warn("Error notifying hulk of failed twofactorauth attempt for $username");
        }
    }
    return;
}

sub _valid_session_data {
    my ( $username, $session_data ) = @_;

    if (   !defined $session_data
        || !defined $session_data->{'user'}
        || !defined $session_data->{'ip_address'}
        || !defined $session_data->{'port'}
        || !defined $session_data->{'local_ip_address'}
        || !defined $session_data->{'local_port'}
        || !defined $session_data->{'origin'}
        || !defined $session_data->{'origin'}{'app'} ) {
        return 0;
    }

    my $session_user = $session_data->{'origin'}{'possessor'} // $session_data->{'authenticated_user'} // $session_data->{'user'};

    if (   !$session_data->{expired}
        && !$session_data->{'tfa_verified'}
        && !$session_data->{needs_auth}
        && $session_user eq $username ) {
        return 1;
    }
    return 0;
}

1;
