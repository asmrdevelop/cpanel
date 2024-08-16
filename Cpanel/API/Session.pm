package Cpanel::API::Session;

# cpanel - Cpanel/API/Session.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::API::Session

=head1 DESCRIPTION

UAPI functions related to the session management.

=cut

#----------------------------------------------------------------------

use Cpanel::AdminBin::Call ();
use Cpanel::Authz          ();
use Cpanel::Exception      ();
use Cpanel::Session::Temp  ();

use Try::Tiny;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 create_temp_user

L<https://go.cpanel.net/create_temp_user>

=cut

sub create_temp_user ( $args, $result ) {

    if ( $ENV{'SESSION_TEMP_USER'} ) {
        my $created = Cpanel::AdminBin::Call::call( 'Cpanel', 'session_call', 'SETUP_TEMP_SESSION', { 'session_temp_user' => $ENV{'SESSION_TEMP_USER'} } );
        if ($created) {
            $result->data( { 'created' => $created, 'session_temp_user' => Cpanel::Session::Temp::full_username_from_temp_user( $ENV{'REMOTE_USER'}, $ENV{'SESSION_TEMP_USER'} ) } );
            return 1;
        }
    }

    $result->data( { 'created' => 0 } );
    return 1;
}

#----------------------------------------------------------------------

=head2 create_webmail_session_for_self

L<https://go.cpanel.net/create_webmail_session_for_self>

=cut

# NB: This function and its mail-user analogue need to call out manually
# to the remote mail node in order to preserve REMOTE_ADDR.

# args: locale, remote_address
# ret: token, session, hostname
sub create_webmail_session_for_self ( $args, $result ) {
    return _create_session(
        $args, $result,
        admin_fn   => 'CREATE_WEBMAIL_SESSION_FOR_SELF',
        admin_args => [],
    );
}

=head2 create_webmail_session_for_mail_user

L<https://go.cpanel.net/create_webmail_session_for_mail_user>

=cut

# args: login, domain, locale, remote_address
# ret: token, session, hostname
#
# If “hostname” is not undef, then the caller can:
#   - access $hostname literally (not recommended)
#   - access mail.$domain:2096
#   - access webmail.$domain
#
sub create_webmail_session_for_mail_user ( $args, $result ) {
    my ( $login, $domain ) = $args->get_length_required( 'login', 'domain' );

    return _create_session(
        $args, $result,
        admin_fn   => 'CREATE_WEBMAIL_SESSION_FOR_MAIL_USER',
        admin_args => [
            login  => $login,
            domain => $domain,
        ],
    );
}

#----------------------------------------------------------------------

sub create_webmail_session_for_mail_user_check_password ( $args, $result ) {
    my ( $login, $domain, $password ) = map { $args->get_length_required($_) } (
        'login',
        'domain',
        'password',
    );

    require Cpanel::Security::Authn::Webmail;
    my ($encrypted_pw);

    my $user_not_found;

    try {
        try {
            Cpanel::Authz::verify_domain_access_or_die($domain);
        }
        catch {
            $user_not_found = 1;
        };

        if ( !$user_not_found ) {
            ($encrypted_pw) = Cpanel::Security::Authn::Webmail::fetch_mail_user_encrypted_password( $login, $domain, $Cpanel::homedir );
            $user_not_found ||= !$encrypted_pw;
        }
    }
    catch {
        if ( try { $_->isa('Cpanel::Exception::UserNotFound') || $_->isa('Cpanel::Exception::DomainDoesNotExist') } ) {
            $user_not_found = 1;
        }
        else {
            local $@ = $_;
            die;
        }
    };

    if ($user_not_found) {
        $result->set_typed_error('UserNotFound');
        die Cpanel::Exception::create( 'UserNotFound', [ name => "$login\@$domain" ] );
    }

    require Cpanel::Security::Authn::Webmail::Password;
    if ( Cpanel::Security::Authn::Webmail::Password::is_suspended( \$encrypted_pw ) ) {
        $result->set_typed_error('Suspended');
        die Cpanel::Exception->create( 'Logins for “[_1]” are suspended.', ["$login\@$domain"] );
    }

    require Cpanel::CheckPass::UNIX;
    if ( !Cpanel::CheckPass::UNIX::checkpassword( $password, $encrypted_pw ) ) {
        $result->set_typed_error('BadPassword');
        die Cpanel::Exception->create('The provided password is incorrect.');
    }

    return create_webmail_session_for_mail_user( $args, $result );
}

#----------------------------------------------------------------------

sub _create_session ( $args, $result, %opts ) {
    my $locale_tag = $args->get('locale') // do {
        require Cpanel::Locale;
        Cpanel::Locale->get_handle()->get_language_tag();
    };

    my %return = (
        hostname => undef,
    );

    my ( $module, $fn ) = ( caller 1 )[3] =~ m<.+::(.+)::(.+)>;

    my %worker_args = (
        %{ $args->get_raw_args_hr() },
        locale => $locale_tag,
    );

    require Cpanel::Validate::IP;

    my $remote_address = $worker_args{'remote_address'};

    if ($remote_address) {
        if ( !Cpanel::Validate::IP::is_valid_ip($remote_address) ) {
            die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid [asis,IP] address.', [$remote_address] );
        }
    }
    elsif ( $remote_address = $ENV{'REMOTE_ADDR'} ) {
        if ( !Cpanel::Validate::IP::is_valid_ip($remote_address) ) {
            my $err = Cpanel::Exception->create_raw('Internal error');
            warn( sprintf "XID %s: “REMOTE_ADDR” environment variable (%s) isn’t a valid IP address!", $err->id(), $remote_address );

            die $err;
        }
    }
    else {
        die Cpanel::Exception->create( 'The system failed to determine a suitable remote [asis,IP] address for the [asis,Webmail] session. Submit a “[_1]”.', ['remote_address'] );
    }

    $worker_args{'remote_address'} ||= $remote_address;

    require Cpanel::LinkedNode::Worker::User;
    my $worker_result = Cpanel::LinkedNode::Worker::User::call_worker_uapi(
        'Mail',
        $module, $fn,
        \%worker_args,
    );

    if ($worker_result) {
        my $from = $worker_result->metadata('proxied_from')->[-1];

        if ( !$worker_result->status() ) {
            die Cpanel::Exception->create_raw( "Remote worker API call from “$from” failed: " . $worker_result->errors_as_string() );
        }

        my $got_hr = $worker_result->data();

        $return{$_} = $got_hr->{$_} for qw( token session );

        $return{'hostname'} = $from;
    }
    else {
        @return{qw( token session )} = Cpanel::AdminBin::Call::call(
            'Cpanel', 'session_call',
            $opts{'admin_fn'},
            @{ $opts{'admin_args'} },
            return_url     => $args->get('return_url'),
            locale         => $locale_tag,
            remote_address => $worker_args{'remote_address'},
        );
    }

    $result->data( \%return );

    return 1;
}

#----------------------------------------------------------------------

my $allow_demo_hr = { allow_demo => 1 };

our %API = (
    create_temp_user                     => $allow_demo_hr,
    create_webmail_session_for_self      => $allow_demo_hr,
    create_webmail_session_for_mail_user => $allow_demo_hr,
);

1;
