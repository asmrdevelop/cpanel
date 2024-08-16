package Cpanel::Admin::Modules::Cpanel::user;

# cpanel - Cpanel/Admin/Modules/Cpanel/user.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent qw( Cpanel::Admin::Base );

use Cpanel                            ();
use Cpanel::Config::CpUserGuard       ();
use Cpanel::Locale                    ();
use Cpanel::Services::Cpsrvd          ();
use Cpanel::Themes::Available         ();
use Cpanel::Config::LocalDomains      ();
use Cpanel::PageRequest               ();
use Cpanel::Exception                 ();
use Cpanel::Mkdir                     ();
use Cpanel::Validate::VirtualUsername ();

sub run ( $self, @args ) {
    local $Cpanel::Carp::OUTPUT_FORMAT = 'xml';

    return $self->SUPER::run(@args);
}

my $locale;

sub _locale {
    return $locale ||= Cpanel::Locale->get_handle();
}

use constant _actions__pass_exception => (
    'CHANGE_THEME',
    'HAS_LOCALDOMAIN',
    'CREATE_INVITE',
    'CREATE_TEAM_INVITE',
);

use constant _actions => (
    _actions__pass_exception(),
);

sub _user_error ($msg) {
    return Cpanel::Exception::create( 'AdminError', [ message => $msg ] );
}

sub CHANGE_THEME {
    my ( $self, $theme ) = @_;

    my $user = $self->get_caller_username();
    Cpanel::initcp($user);

    $theme //= q<>;

    if ( $theme !~ m/^[a-zA-Z0-9_-]+$/i ) {
        die _user_error( _locale()->maketext( "The provided theme name “[_1]” is not a valid theme name.", $theme ) );
    }

    unless ( Cpanel::Themes::Available::is_theme_available($theme) ) {
        die _user_error( _locale()->maketext( "The provided theme “[_1]” is not available to this user.", $theme ) );
    }

    if ( !Cpanel::hasfeature('theme-switch') ) {
        die _user_error( _locale()->maketext('This user does not have access to the theme-switch feature.') );
    }

    my $cpuser = Cpanel::Config::CpUserGuard->new($user);
    if ($cpuser) {
        if ( $cpuser->{'data'}->{'RS'} =~ /mail$/ ) {
            die _user_error( _locale()->maketext("Users using mail themes may not change their own theme, please ask your provider to change your theme for you.") );
        }
        $cpuser->{'data'}->{'RS'} = $theme;
        $cpuser->save();
        Cpanel::Services::Cpsrvd::signal_users_cpsrvd_to_reload($user);
    }
    else {
        die "Could not load the user file for user “$user";
    }

    return;
}

# Determines if the user both owns a domain and if the domain is listed in /etc/localdomains.
sub HAS_LOCALDOMAIN {
    my ( $self, $domain ) = @_;

    my $user = $self->get_caller_username();
    Cpanel::initcp($user);

    $domain or die _user_error( _locale()->maketext('HAS_LOCALDOMAIN called with no domain') );

    # Domain is not owned by this user.
    if ( !$self->cpuser_owns_domain($domain) ) {
        return 0;
    }

    # Load /etc/localdomains.
    my $localdomains_ref = Cpanel::Config::LocalDomains::loadlocaldomains();

    # Return if the domain is mentioned there.
    return $localdomains_ref->{$domain} ? 1 : 0;
}

sub CREATE_INVITE {
    my ( $self, $user ) = @_;
    $user or die Cpanel::Exception::create( 'MissingParameter', [ name => 'user' ] );
    Cpanel::Validate::VirtualUsername::validate_or_die($user);
    die if $user =~ /\.\./;

    my $cpuser = $self->get_caller_username();
    Cpanel::initcp($cpuser);

    my ( $mailbox, $domain ) = split( /[@]/, $user, 2 );

    # Make sure the subaccount exists (validating the subaccount also validates that the user owns the domain)
    $self->verify_that_cpuser_has_subaccount( $mailbox, $domain );

    # Setup the folders that are pre-requsites for
    # setting up a session for the invite.
    my $invites_path = '/var/cpanel/invites';
    Cpanel::Mkdir::ensure_directory_existence_and_mode( $invites_path, 0700 );

    # Create a session for the invite
    my $session = Cpanel::PageRequest->new( path => "$invites_path/$user" );
    $session->data(
        {
            user => $user,

            # Preserve the cookie in the data since the first request
            # in the cgi will generate a different cookie, but we need
            # to compare the one here with what the user submits in
            # their link.
            invite_cookie => $session->cookie,
        }
    );
    $session->save_session();

    return $session->cookie;
}

sub CREATE_TEAM_INVITE {
    my ( $self, $user ) = @_;
    $user or die Cpanel::Exception::create( 'MissingParameter', [ name => 'user' ] );

    # Setup the folders that are pre-requsites for
    # setting up a session for the invite.
    my $invites_path = '/var/cpanel/team_invites';
    Cpanel::Mkdir::ensure_directory_existence_and_mode( $invites_path, 0700 );

    # Create a session for the invite
    my $session = Cpanel::PageRequest->new( path => "$invites_path/$user" );
    $session->data(
        {
            user => $user,

            # Preserve the cookie in the data since the first request
            # in the cgi will generate a different cookie, but we need
            # to compare the one here with what the user submits in
            # their link.
            invite_cookie => $session->cookie,
            account_type  => 'team_user',
        }
    );
    $session->save_session();

    return $session->cookie;
}

1;
