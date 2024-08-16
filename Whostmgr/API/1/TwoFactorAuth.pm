package Whostmgr::API::1::TwoFactorAuth;

# cpanel - Whostmgr/API/1/TwoFactorAuth.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;
use Cpanel::Imports;

use Cpanel::Notify                                   ();
use Cpanel::Signal                                   ();
use Whostmgr::ACLS                                   ();
use Whostmgr::Authz                                  ();
use Cpanel::Hostname                                 ();
use Cpanel::Exception                                ();
use Whostmgr::AcctInfo                               ();
use Whostmgr::Services::Load                         ();
use Cpanel::SecurityPolicy                           ();
use Whostmgr::API::1::Utils                          ();
use Cpanel::AcctUtils::Domain                        ();
use Cpanel::Config::CpConfGuard                      ();
use Cpanel::Security::Authn::TwoFactorAuth           ();
use Cpanel::Security::Authn::TwoFactorAuth::Google   ();
use Cpanel::Config::userdata::TwoFactorAuth::Secrets ();
use Cpanel::Config::userdata::TwoFactorAuth::Issuers ();

use constant NEEDS_ROLE => {
    twofactorauth_disable_policy      => undef,
    twofactorauth_enable_policy       => undef,
    twofactorauth_generate_tfa_config => undef,
    twofactorauth_get_issuer          => undef,
    twofactorauth_get_user_configs    => undef,
    twofactorauth_policy_status       => undef,
    twofactorauth_remove_user_config  => undef,
    twofactorauth_set_issuer          => undef,
    twofactorauth_set_tfa_config      => undef,
};

sub twofactorauth_policy_status {
    my ( undef, $metadata ) = @_;

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return { 'is_enabled' => Cpanel::Security::Authn::TwoFactorAuth::is_enabled() };
}

sub twofactorauth_enable_policy {
    my ( undef, $metadata ) = @_;

    if ( !_set_sec_policy(1) ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = locale->maketext('Failed to enable the Two-Factor Authentication security policy.');
        return;
    }
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return;
}

sub twofactorauth_disable_policy {
    my ( undef, $metadata ) = @_;

    if ( !_set_sec_policy(0) ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = locale->maketext('Failed to disable Two-Factor Authentication security policy.');
        return;
    }
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return;
}

sub twofactorauth_get_user_configs {
    my ( $args, $metadata ) = @_;

    my $single_user = $args->{'user'} || '';
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    my $output;
    try {
        my $has_root      = Whostmgr::ACLS::hasroot();
        my $tfa_userdata  = Cpanel::Config::userdata::TwoFactorAuth::Secrets->new( { 'read_only' => 1 } )->read_userdata();
        my $user_accts_hr = Whostmgr::AcctInfo::get_accounts( $has_root ? '' : $ENV{'REMOTE_USER'} );
        $user_accts_hr->{'root'} = 'n/a' if $has_root;

        # If the request was for a particular user, then make sure that the caller
        # has ownership over that user before returning any data.
        if ( $single_user && !( exists $user_accts_hr->{$single_user} || $single_user eq $ENV{'REMOTE_USER'} ) ) {
            $metadata->{'result'} = 0;
            $metadata->{'reason'} = locale->maketext( 'You do not have access to an account named “[_1]”.', $single_user );
        }
        else {
            my @users = ( $single_user ? $single_user : ( keys %{$user_accts_hr} ) );
            foreach my $user (@users) {
                $output->{$user} = {
                    'is_enabled'     => ( exists $tfa_userdata->{$user} ? 1                                      : 0 ),
                    'primary_domain' => ( $user eq 'root'               ? scalar Cpanel::Hostname::gethostname() : scalar Cpanel::AcctUtils::Domain::getdomain($user) ),
                };
            }
        }
    }
    catch {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = locale->maketext( 'Failed to fetch user configurations: [_1]', Cpanel::Exception::get_string($_) );
    };
    return if !$metadata->{'result'};

    return $output;
}

sub twofactorauth_remove_user_config {
    my ( $args, $metadata ) = @_;

    my $users_ar = _parse_users($args);
    if ( !scalar @{$users_ar} ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = locale->maketext('No users specified.');
        return;
    }

    my %email_opts;
    $email_opts{'origin'} = $args->{'origin'} if $args->{'origin'};

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    my $output = {
        'failed'         => {},
        'users_modified' => [],
    };
    try {
        my $tfa_userdata = Cpanel::Config::userdata::TwoFactorAuth::Secrets->new();
        foreach my $user ( @{$users_ar} ) {
            if ( my $error = _verify_account_access($user) ) {
                $output->{'failed'}->{$user} = locale->maketext( 'You are not authorized to modify “[_1]”: [_2]', $user, $error );
                next;
            }
            $tfa_userdata->remove_tfa_for_user($user);
            push @{ $output->{'users_modified'} }, $user;

            # Renaming the tfa user entry to team_user login name
            my $tfa_user_name = $ENV{'TEAM_USER'} ? "$ENV{'TEAM_USER'}\@$ENV{'TEAM_LOGIN_DOMAIN'}" : $user;
            try { _notify_user_disable( $tfa_user_name, %email_opts ) } if $user eq $ENV{'REMOTE_USER'};
        }
        $tfa_userdata->save_changes_to_disk() if scalar @{ $output->{'users_modified'} };
    }
    catch {
        # TODO: Remove or keep?
        logger->info($_);
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = locale->maketext( 'Failed to remove two-factor authentication: [_1]', Cpanel::Exception::get_string($_) );
    };

    return $output;
}

sub twofactorauth_set_issuer {
    my ( $args, $metadata ) = @_;

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    try {
        my $issuer          = _validate_issuer( $args->{'issuer'} );
        my $issuer_userdata = Cpanel::Config::userdata::TwoFactorAuth::Issuers->new();
        $issuer_userdata->set_issuer( $ENV{'REMOTE_USER'}, $issuer );
        $issuer_userdata->save_changes_to_disk();
    }
    catch {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = locale->maketext( 'Failed to set issuer: [_1]', Cpanel::Exception::get_string($_) );
    };

    return;
}

sub twofactorauth_get_issuer {
    my ( undef, $metadata ) = @_;

    my $output;
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    try {
        my $issuer_userdata = Cpanel::Config::userdata::TwoFactorAuth::Issuers->new( { 'read_only' => 1 } );
        $output->{'issuer'}             = $issuer_userdata->get_issuer( $ENV{'REMOTE_USER'} );
        $output->{'system_wide_issuer'} = $issuer_userdata->get_system_wide_issuer();
    }
    catch {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = locale->maketext( 'Failed to get issuer: [_1]', Cpanel::Exception::get_string($_) );
    };

    return $output;
}

sub twofactorauth_generate_tfa_config {
    my ( $args, $metadata ) = @_;
    $args = {} if !$args || ref $args ne 'HASH';

    # NOTE: C<$args> will only be populated when this function
    # is called from the twofactorauth adminbin.
    #
    # XML-API will strip all input from the user,
    # so this call will only generate the configuration
    # for the REMOTE_USER when the [json|xml]-api call is made.
    my $user = $args->{'user'} || $ENV{'REMOTE_USER'};
    my $output;

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    try {
        my $generated_secret = Cpanel::Security::Authn::TwoFactorAuth::Google::generate_random_base32_secret();
        my $auth             = Cpanel::Security::Authn::TwoFactorAuth::Google->new(
            {
                'secret'       => $generated_secret,
                'account_name' => $user,
                'issuer'       => scalar Cpanel::Config::userdata::TwoFactorAuth::Issuers->new( { 'read_only' => 1 } )->get_issuer($user),
            }
        );
        $output = {
            'secret'      => $generated_secret,
            'otpauth_str' => $auth->otpauth_str(),
        };
    }
    catch {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = locale->maketext( 'Failed to generate two-factor authentication configuration: [_1]', Cpanel::Exception::get_string($_) );
    };

    return $output;
}

sub twofactorauth_set_tfa_config {
    my ( $args, $metadata ) = @_;

    my $user       = $args->{'user'} || $ENV{'REMOTE_USER'};
    my $tfa_config = {
        'secret'       => $args->{'secret'},
        'account_name' => $user,
        'issuer'       => 'n/a',
    };

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    my $auth;
    try {
        $auth = Cpanel::Security::Authn::TwoFactorAuth::Google->new($tfa_config);
    }
    catch {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = Cpanel::Exception::get_string($_);
    };
    return if !$auth;

    if ( !$auth->verify_token( $args->{'tfa_token'} ) ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = locale->maketext('The security code is invalid.');
        return;
    }
    my $success = 0;
    my $overwrote_previous;
    try {
        my $tfa_manager = Cpanel::Config::userdata::TwoFactorAuth::Secrets->new();

        $overwrote_previous = exists $tfa_manager->read_userdata()->{$user};
        $tfa_manager->configure_tfa_for_user(
            {
                'username' => $user,
                'secret'   => $tfa_config->{'secret'},
            }
        );
        $tfa_manager->save_changes_to_disk();
        $success = 1;
    }
    catch {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = locale->maketext('Failed to set user configuration.');
    };

    my %email_opts = ( overwrote_prev => $overwrote_previous );
    $email_opts{'origin'} = $args->{'origin'} if $args->{'origin'};

    # Renaming the tfa user entry to team_user login name
    my $tfa_user_name = $ENV{'TEAM_USER'} ? "$ENV{'TEAM_USER'}\@$ENV{'TEAM_LOGIN_DOMAIN'}" : $user;
    try { _notify_user_enable( $tfa_user_name, %email_opts ) } if $success;

    return { 'success' => $success };
}

sub _verify_account_access {
    my $user = shift;

    # verify_account_access() checks for a cpuser file,
    # since 'root' doesn't have a cpuser file, we need to
    # account for that instance here.
    return if $user eq 'root' && Whostmgr::ACLS::hasroot();

    my $error;
    try {
        # dies if the user spacified can not be managed by the $ENV{'REMOTE_USER'}
        Whostmgr::Authz::verify_account_access($user);
    }
    catch {
        $error = Cpanel::Exception::get_string($_);
        chomp $error;
    };
    return $error;
}

sub _notify_user_enable {
    my ( $user, %opts ) = @_;

    return if $user =~ /\@/ && !$ENV{TEAM_USER};    # webmail user does not have notification preferences
    return if !_notifications_enabled($user);

    try {
        my $iface = _action_url_interface( $user, $opts{origin} || 'whm' );
        if ( $iface && !$opts{action_url} ) {
            my $hostname = Cpanel::Hostname::gethostname();
            $opts{action_url} = "https://$hostname:2087/scripts7/twofactorauth/myaccount"         if $iface eq 'whostmgr';
            $opts{action_url} = "https://$hostname:2083/frontend/jupiter/security/2fa/index.html" if $iface eq 'jupiter';
        }
    };

    Cpanel::Notify::notification_class(
        class            => 'TwoFactorAuth::UserEnable',
        application      => 'TwoFactorAuth::UserEnable',
        constructor_args => [
            notification_targets_user_account => ( $user eq 'root' ? 0 : 1 ),
            username                          => $user,                               # Identify the cPanel account affected
            user                              => $user,                               # Pass the value on to the icontact_template
            to                                => $user,                               # Where the email should be sent
            source_ip_address                 => $ENV{'REMOTE_ADDR'},
            origin                            => 'whm',
            team_account                      => defined $ENV{'TEAM_USER'} ? 1 : 0,
            %opts,
        ],
    );
    return 1;
}

sub _notify_user_disable {
    my ( $user, %opts ) = @_;

    return if $user =~ /\@/ && !$ENV{TEAM_USER};    # webmail user does not have notification preferences
    return if !_notifications_enabled($user);

    try {
        my $iface = _action_url_interface( $user, $opts{origin} || 'whm' );
        if ( $iface && !$opts{action_url} ) {
            my $hostname = Cpanel::Hostname::gethostname();
            $opts{action_url} = "https://$hostname:2087/scripts7/twofactorauth/myaccount" if $iface eq 'whostmgr';

            # We don't use setup.html since we won't know whether the user is effectively configuring or reconfiguring.
            $opts{action_url} = "https://$hostname:2083/frontend/jupiter/security/2fa/index.html" if $iface eq 'jupiter';
        }
    };

    Cpanel::Notify::notification_class(
        class            => 'TwoFactorAuth::UserDisable',
        application      => 'TwoFactorAuth::UserDisable',
        constructor_args => [
            notification_targets_user_account => ( $user eq 'root' ? 0 : 1 ),
            username                          => $user,                                                  # Identify the cPanel account affected
            user                              => $user,                                                  # Pass the value on to the icontact_template
            to                                => $user,                                                  # Where the email should be sent
            source_ip_address                 => $ENV{'REMOTE_ADDR'},
            origin                            => 'whm',
            policy_enabled                    => Cpanel::Security::Authn::TwoFactorAuth::is_enabled(),
            team_account                      => defined $ENV{'TEAM_USER'} ? 1 : 0,
            %opts,
        ],
    );
    return 1;
}

sub _notifications_enabled {
    my ($user) = @_;

    require Cpanel::ContactInfo;
    my $cinfo = Cpanel::ContactInfo::get_contactinfo_for_user($user);
    return $cinfo->{'notify_twofactorauth_change'};
}

sub _parse_users {
    my $args  = shift;
    my @users = map { $args->{$_} } grep { $_ =~ /^user(?:\-\d+)?$/ } ( keys %{$args} );
    return \@users;
}

sub _validate_issuer {
    my $issuer = shift;

    # Strip opening and ending quotes from the issuer name
    $issuer =~ s/^['"]|['"]$//g;
    return undef if not length $issuer;

    die Cpanel::Exception::create(
        'InvalidParameter',
        'The “[_1]” parameter must be less than or equal to 32 characters in length. It can only use spaces and the following characters: [join, ,_2]',
        [
            'issuer',
            [ "a-z", "A-Z", "0-9", ".", "_", "-" ]
        ]
    ) if $issuer !~ m/^[ a-zA-Z0-9\._\-]{1,32}$/;

    return $issuer;
}

# TODO: should we refactor this into a Cpanel::Config::SecurityPolicy namespace instead?
# There is similar logic in the securitypolicy.cgi, but doesn't appear to be anywhere else.
sub _set_sec_policy {
    my $value = shift;

    my $success = 0;
    try {
        my $cpconf_guard = Cpanel::Config::CpConfGuard->new();
        $cpconf_guard->{'data'}->{'SecurityPolicy::TwoFactorAuth'} = $value;
        $cpconf_guard->save();
        Cpanel::SecurityPolicy::loadmodules( 'conf' => scalar $cpconf_guard->config_copy(), 'verbose' => 1 );
        Whostmgr::Services::Load::reload_service('cphulk');
        Cpanel::Signal::send_hup_cpsrvd();
        $success = 1;
    }
    catch {
        # TODO: Remove or keep?
        logger->info($_);
    };

    return $success;
}

sub _action_url_interface {
    my ( $user, $origin ) = @_;

    # Root can only interact via WHM.
    return 'whostmgr' if $user eq 'root';

    # TODO: Webmail users.
    if ( $user =~ tr/@// ) {
        die "Webmail users not yet supported";
    }

    # If run through WHM, the user must be able to access the WHM script.
    return 'whostmgr' if $origin eq 'whm';

    # Make sure cPanel users have Paper Lantern/jupiter before offering link.
    require Cpanel::Config::LoadCpUserFile;
    my $conf = Cpanel::Config::LoadCpUserFile::load($user);
    return 'jupiter' if $conf->{'RS'} eq 'jupiter';

    # Fallback to WHM for resellers.
    require Cpanel::Reseller;
    return 'whostmgr' if Cpanel::Reseller::isreseller($user);

    # Don't show an action link.
    return;
}

1;
