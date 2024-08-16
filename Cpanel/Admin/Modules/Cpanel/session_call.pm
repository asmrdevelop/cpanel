package Cpanel::Admin::Modules::Cpanel::session_call;

# cpanel - Cpanel/Admin/Modules/Cpanel/session_call.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Admin::Modules::Cpanel::session_call

=head1 DESCRIPTION

This module contains admin logic for session management.

=cut

#----------------------------------------------------------------------

use parent qw( Cpanel::Admin::Base );

use Cpanel::Exception ();

use constant _actions => (
    'CREATE_WEBMAIL_SESSION_FOR_SELF',
    'CREATE_WEBMAIL_SESSION_FOR_MAIL_USER',
    'SETUP_TEMP_SESSION',
    'REGISTER_PROCESS',
);

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 ($token, $session) = CREATE_WEBMAIL_SESSION_FOR_SELF($self, %opts)

Returns a security token (e.g., C</cpsess123456>) and a session string
that the caller can use to use Webmail on the local server.

%opts are:

=over

=item * C<remote_address> - The address from which the client will
connect to use Webmail.

=item * C<locale> - The locale tag (e.g., C<en>) for the Webmail session.

=back

=cut

sub CREATE_WEBMAIL_SESSION_FOR_SELF ( $self, %opts ) {
    return $self->_create_webmail_session( $self->get_caller_username(), \%opts );
}

=head2 ($token, $session) = CREATE_WEBMAIL_SESSION_FOR_MAIL_USER($self, %opts)

Like C<CREATE_WEBMAIL_SESSION_FOR_SELF()> but for a webmail user.

%opts are:

=over

=item * C<login> - The user address’s local part.

=item * C<domain> - The user address’s domain.

=item * … plus everything that C<CREATE_WEBMAIL_SESSION_FOR_SELF()> needs
addition of

=back

=cut

sub CREATE_WEBMAIL_SESSION_FOR_MAIL_USER ( $self, %opts ) {
    my @lack = grep { !length $opts{$_} } qw( login domain );
    die "Need: [@lack]" if @lack;

    my $username = "$opts{'login'}\@$opts{'domain'}";

    require Cpanel::AccessControl;

    $self->whitelist_exceptions(
        ['Cpanel::Exception::UserNotFound'],
        sub {
            Cpanel::AccessControl::verify_user_access_to_account(
                $self->get_caller_username() => $username,
            );
        },
    );

    return $self->_create_webmail_session( $username, \%opts );
}

sub _get_and_validate_locale ( $self, $opts_hr ) {
    my $value = $opts_hr->{'locale'};

    if ( !length $value ) {
        $self->whitelist_exception('Cpanel::Exception::MissingParameter');
        die Cpanel::Exception::create(
            'MissingParameter',
            [
                name => 'locale',
            ]
        );
    }

    require Cpanel::Locale;
    require Cpanel::Locale::Utils::Display;

    my @locales = Cpanel::Locale::Utils::Display::get_locale_list( Cpanel::Locale->get_handle() );

    if ( !grep { $_ eq $value } @locales ) {
        $self->whitelist_exception('Cpanel::Exception::InvalidParameter');
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” does not refer to any of this system’s locales.', [$value] );
    }

    return $value;
}

sub _get_and_validate_remote_addr ( $self, $opts_hr ) {
    my $remote_addr = $opts_hr->{'remote_address'};

    if ( !length $remote_addr ) {
        $self->whitelist_exception('Cpanel::Exception::MissingParameter');
        die Cpanel::Exception::create(
            'MissingParameter',
            [
                name => 'remote_address',
            ]
        );
    }

    require Cpanel::Validate::IP;

    if ( !Cpanel::Validate::IP::is_valid_ip($remote_addr) ) {
        $self->whitelist_exception('Cpanel::Exception::InvalidParameter');
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid [asis,IP] address.', [$remote_addr] );
    }

    return $remote_addr;
}

sub _create_webmail_session ( $self, $username, $opts_hr ) {
    my $locale = $self->_get_and_validate_locale($opts_hr);

    my $remote_addr = $self->_get_and_validate_remote_addr($opts_hr);

    my $cpusername = $self->get_caller_username();

    require Cpanel::Session;

    # We could offload token creation to the caller, but then we’d
    # have to validate it, and there’s no particular reason to separate
    # token creation from the session creation.
    my $token = Cpanel::Session::generate_new_security_token();

    my $session_obj = Cpanel::Session->new();

    my $this_func_name = ( caller 1 )[3] =~ s<.+::><>r;

    my $randsession = $session_obj->create(
        'user'    => $username,
        'session' => {
            'user'                                    => $username,
            'successful_external_auth_with_timestamp' => time(),
            'cp_security_token'                       => $token,
            'service'                                 => 'webmail',

            'session_locale' => $locale,

            # This should not require 2FA since it’s already authenticated.
            'tfa_verified' => 1,

            'creator' => $cpusername,

            'return_url' => $opts_hr->{'return_url'},

            'origin' => {
                'app'     => ref($self),
                'method'  => $this_func_name,
                'creator' => $cpusername,
                'address' => $remote_addr,
            },
        },
        'tag' => $this_func_name,
    );

    if ( !$randsession ) {
        die "Failed to create a webmail session for “$username”!";
    }

    return ( $token, $randsession );
}

# It might be ideal if we just used the cpwrapd peer PID, but we can’t
# rely on that to be the actual PID that the user wants to register.
sub REGISTER_PROCESS {
    my ( $self, $session_id, $pid ) = @_;

    my $username = $self->get_caller_username();

    # TODO: Is this logic somewhere else? It would be ideal not to parse
    # the session ID here.

    # Team user publishing a sitejet website have their own session id
    $username = $ENV{'TEAM_USER'} . '@' . $ENV{'TEAM_LOGIN_DOMAIN'} if $ENV{'TEAM_USER'};
    if ( 0 != index( $session_id, "$username:" ) ) {
        die "Invalid session ID!";    #don’t disclose
    }

    require Cpanel::LoadFile;
    my $status = Cpanel::LoadFile::load("/proc/$pid/status");
    my @uids   = ( $status =~ m<^uid:\s+([0-9]+)\s+([0-9]+)\s+([0-9]+)\s+([0-9]+)>im );

    my $ok = !grep { $_ != $self->get_cpuser_uid() } @uids;

    if ( !$ok ) {
        die "Unknown or unowned process: $pid\n";
    }

    require Cpanel::Session::Load;

    my $session_ref = Cpanel::Session::Load::loadSession($session_id);
    if ( !%$session_ref ) {
        die "Unrecognized session ID: $session_id\n";
    }

    require Cpanel::Session::RegisteredProcesses;
    Cpanel::Session::RegisteredProcesses::add_and_save(
        $session_id,
        $session_ref,
        $pid,
    );

    return;
}

sub SETUP_TEMP_SESSION {
    my ( $self, $ref ) = @_;

    my $caller_username = $self->get_caller_username();

    if ( !$ref->{'session_temp_user'} ) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'session_temp_user' ] );
    }

    require Cpanel::Session::Temp;
    my $session_temp_user = $ref->{'session_temp_user'};
    my $session           = Cpanel::Session::Temp::get_session_from_temp_username($session_temp_user);
    if ( !$session ) {
        die "The session temp user “$session_temp_user” does not have a valid session.";
    }
    if ( $session !~ m{^\Q$caller_username\E:} ) {
        die "The session for the temp user “$session_temp_user” does not belong to “$caller_username”";
    }

    require Cpanel::Session::Load;
    my $SESSION_ref = Cpanel::Session::Load::loadSession($session);

    # The temp users have already been created
    if ( !$SESSION_ref->{'session_needs_temp_user'} ) { return 0; }

    require Cpanel::Session::Modify;
    #
    # Generate temp session users since we are not logged in with the account password
    #
    my $session_mod = Cpanel::Session::Modify->new($session);

    # Check again incase the user was created between when we locked
    # and loaded the session above
    if ( !$session_mod->get('session_needs_temp_user') ) {
        $session_mod->abort();
        return 0;
    }

    if ( $session_temp_user ne $session_mod->get('session_temp_user') ) {

        # This should never happen
        die "The session_temp_user did not match the session";
    }
    my $session_temp_pass = $session_mod->get('session_temp_pass');

    Cpanel::Session::Temp::create_temp_user( $caller_username, $session_temp_user, $session_temp_pass ) or die 'Failed to setup the temp session user';

    $session_mod->set( 'created_session_temp_user', '1' );
    $session_mod->delete('session_needs_temp_user');
    $session_mod->save();

    return 1;
}
1;
