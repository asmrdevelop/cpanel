package Cpanel::ContactInfo::Sync;

# cpanel - Cpanel/ContactInfo/Sync.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::PwCache                      ();
use Cpanel::PwCache                      ();
use Cpanel::PwCache::Build               ();
use Cpanel::AdminBin::Serializer         ();    # # PPI USE OK - force load so that loadcpuserfile isn't slow
use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::DataStore                    ();
use Cpanel::Config::CpUserGuard          ();
use Cpanel::Config::Users                ();
use Cpanel::Email::Accounts              ();
use Cpanel::Debug                        ();
use Cpanel::ContactInfo::FlagsCache      ();
use Cpanel::ContactInfo::Notify          ();
use Cpanel::CustInfo::Model              ();
use Cpanel::Validate::FilesystemNodeName ();
use Cpanel::Validate::IP                 ();

use Try::Tiny;

sub sync_contact_info {
    my ( $user, $homedir, $uid, $gid ) = @_;

    $homedir ||= Cpanel::PwCache::gethomedir($user);

    return if !$homedir;

    if ( !$uid || !$gid ) {
        ( $uid, $gid ) = ( Cpanel::PwCache::getpwnam_noshadow($user) )[ 2, 3 ];
    }

    local $YAML::Syck::LoadBlessed = 0;

    # sync_contact_info is NEVER called for virtual users
    # If you need to sync a virtual user look at sync_mail_users_contact_info
    my $fields = Cpanel::CustInfo::Model::get_active_contact_fields($Cpanel::CustInfo::Model::SYSTEM_USER);

    my $contact_info_conf;
    Cpanel::AccessIds::ReducedPrivileges::call_as_user(
        sub {
            $contact_info_conf = Cpanel::DataStore::fetch_ref( $homedir . '/.cpanel/contactinfo' );
            if ( !ref $contact_info_conf || ref $contact_info_conf ne 'HASH' ) { $contact_info_conf = {}; }

            1;    #magic true value
        },
        $uid,
        $gid
    ) || warn 'Could not Cpanel::AccessIds::ReducedPrivileges::call_as_user';

    if ( my $cpuser = Cpanel::Config::CpUserGuard->new($user) ) {
        my $notification_prefs = Cpanel::ContactInfo::Notify::get_notification_preference_from_contact_data( $cpuser->{'data'} );
        my $cpuser_emails      = $cpuser->{'data'}->contact_emails_ar();
        my $notifications_hr   = {};
        foreach my $key ( keys %{$fields} ) {

            my $cpuser_key = $fields->{$key}{'cpuser_key'};

            # Don’t sync email fields:
            next if grep { $key eq $_ } Cpanel::CustInfo::Model::EMAIL_FIELDS;

            my $conf_value = $contact_info_conf->{$key};

            if ( defined $contact_info_conf->{$key} ) {

                # This call will return a notification based upon the preferences
                # as defined in get_notification_preference_from_contact_data:
                #
                # notify_contact_address_change
                # notify_password_change_notification_disabled
                # notify_account_login_notification_disabled
                # notify_contact_address_change_notification_disabled
                # notify_twofactorauth_change_notification_disabled
                my $notification_delta_hr = Cpanel::ContactInfo::Notify::get_notification_delta(
                    'key_notification_preference' => $notification_prefs->{$cpuser_key},
                    'new_value'                   => $conf_value,
                    'current_value'               => $cpuser->{'data'}{$cpuser_key},
                );

                $notifications_hr->{$cpuser_key} = $notification_delta_hr if $notification_delta_hr;
            }

            if ( $fields->{$key}{'validator'}->($conf_value) ) {
                $cpuser->{'data'}->{$cpuser_key} = $conf_value;
            }

            # If we don't have a value, insert the default value.
            # We always need to fill the missing key/values in the cpusers file
            # if we do not have values for them so we do no sync over and over
            if ( !length $cpuser->{'data'}->{$cpuser_key} ) {
                $cpuser->{'data'}{$cpuser_key} = $fields->{$key}{'default'};
            }
        }
        $cpuser->save();

        if ( keys %$notifications_hr ) {

            # If we ever add other ways to update contact info, make a function to validate
            # the origin from $contact_info_conf. Right now 'cpanel' is the only valid value
            my $origin = ( exists $contact_info_conf->{'origin'} ) ? 'cpanel' : undef;
            my $ip     = _get_ip_from_contact_info($contact_info_conf);

            $notifications_hr->{'cpuser_emails'} = $cpuser_emails;
            Cpanel::ContactInfo::Notify::send_contactinfo_change_notifications_to_user(
                'username'         => $user,
                'to_user'          => $user,
                'origin'           => $origin,
                'ip'               => $ip,
                'notifications_hr' => $notifications_hr
            );
        }
    }
    else {
        Cpanel::Debug::log_warn("Could not update user file for '$user'");
    }

    my $user_notification_state_obj = Cpanel::ContactInfo::FlagsCache::get_user_flagcache( 'user' => $user );

    foreach my $key ( keys %{$fields} ) {
        next if !$fields->{$key}{'touchfile'};

        $user_notification_state_obj->set_state( $key, $contact_info_conf->{$key} ? 1 : 0 );
    }

    return 1;
}

sub sync_all_users_contact_info {
    my %CPUSERS     = map { $_ => 1 } Cpanel::Config::Users::getcpusers();
    my $pwcache_ref = Cpanel::PwCache::Build::fetch_pwcache();
    foreach my $pw ( grep { $CPUSERS{ $_->[0] } } @$pwcache_ref ) {
        sync_contact_info( $pw->[0], $pw->[7], $pw->[2], $pw->[3] );
        sync_mail_users_contact_info( 'user' => $pw->[0], 'homedir' => $pw->[7], 'uid' => $pw->[2], 'gid' => $pw->[3] );
    }
    return 1;
}

###########################################################################
#
# Method:
#   sync_mail_users_contact_info
#
# Description:
#   This function goes through the mail accounts owned by a cPanel user and syncs the notification flags
#   for all accounts or a specific account.
#
# Parameters (accepts a hash of OPTS):
#   user         - The user for which to perform the mail user contact flag sync.
#   target_email - The optional email account for which to sync contact flags. If this is not supplied all
#                  the mail accounts owned by the specified 'user' will be synced.
#   homedir      - The optional homedir of the specified 'user'. This will be obtained from the username if not supplied.
#   uid          - The optional uid of the specified 'user'. This will be obtained from the username if not supplied.
#   gid          - The optional gid of the specified 'user'. This will be obtained from the username if not supplied.
#
# Exceptions:
#   None currently.
#
# Returns:
#   This function returns empty list if unsuccessful in syncing the mail user contact flags. Otherwise it will return 1.
#
sub sync_mail_users_contact_info {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my (%OPTS) = @_;

    my ( $user, $homedir, $target_email, $uid, $gid ) = @OPTS{qw( user homedir email uid gid )};

    return if !$user;

    $homedir ||= Cpanel::PwCache::gethomedir($user);

    return if !$homedir;

    if ( !$uid || !$gid ) {
        ( $uid, $gid ) = ( Cpanel::PwCache::getpwnam_noshadow($user) )[ 2, 3 ];
    }

    my ( $email_user, $email_domain );
    if ($target_email) {
        ( $email_user, $email_domain ) = split( '@', $target_email, 2 );
        return if !Cpanel::Validate::FilesystemNodeName::is_valid($email_user);
        return if !Cpanel::Validate::FilesystemNodeName::is_valid($email_domain);
    }

    local $YAML::Syck::LoadBlessed = 0;

    my $email_users_contact_info_ar;
    Cpanel::AccessIds::ReducedPrivileges::call_as_user(
        sub {
            $email_users_contact_info_ar = [];

            local $Cpanel::user;
            my ( $email_users_hr, $_manage_err ) = Cpanel::Email::Accounts::manage_email_accounts_db( 'event' => 'fetch' );
            die $_manage_err if $_manage_err;
            return 1         if !keys %$email_users_hr;

            for my $domain ( keys %$email_users_hr ) {
                next if $email_domain && $domain ne $email_domain;
                next if index( $domain, '__' ) == 0 || index( $domain, '*' ) == 0;    # skip __version and wildcard domains
                next if !Cpanel::Validate::FilesystemNodeName::is_valid($domain);
                next if !keys %{ $email_users_hr->{$domain}{'accounts'} };

                for my $account ( keys %{ $email_users_hr->{$domain}{'accounts'} } ) {
                    next if $email_user && $account ne $email_user;
                    next if !Cpanel::Validate::FilesystemNodeName::is_valid($account);

                    my $contact_info_file = $homedir . "/etc/$domain/$account/.cpanel/contactinfo";
                    next if !-f $contact_info_file;

                    my $contact_prefs = Cpanel::DataStore::fetch_ref($contact_info_file);
                    next if !keys %$contact_prefs;

                    push @{$email_users_contact_info_ar},
                      {
                        'email_user'    => $account,
                        'domain'        => $domain,
                        'contact_prefs' => $contact_prefs,
                      };

                    last if $email_user && $account eq $email_user;
                }

                last if $email_domain && $domain eq $email_domain;
            }

            1;    #magic true value
        },
        $uid,
        $gid
    ) || warn 'Could not Cpanel::AccessIds::ReducedPrivileges::call_as_user';

    if ( !@$email_users_contact_info_ar ) {
        return if $target_email;
        return 1;
    }

    my $webmail_fields                    = Cpanel::CustInfo::Model::get_active_webmail_contact_fields();
    my @webmail_field_keys_with_touchfile = grep { $webmail_fields->{$_}{'touchfile'} } keys %$webmail_fields;
    return 1 if !@webmail_field_keys_with_touchfile;    # If hulk is disabled

    for my $email_user_info (@$email_users_contact_info_ar) {
        _create_mail_user_notification_flags(
            %$email_user_info,
            'user'             => $user,
            'touchfile_fields' => \@webmail_field_keys_with_touchfile,
        );
    }

    return 1;
}

sub _get_ip_from_contact_info {
    my ($contact_info_hr) = @_;

    my $possible_ip = $contact_info_hr->{'ip'};
    return if !$possible_ip;

    return $possible_ip if Cpanel::Validate::IP::is_valid_ip($possible_ip);

    return;
}

sub _create_mail_user_notification_flags {
    my (%OPTS) = @_;

    my ( $user, $email_user, $domain, $contact_prefs_hr, $touchfile_fields_ar ) = @OPTS{qw( user email_user domain contact_prefs touchfile_fields )};

    my $virtual_user_state_obj = Cpanel::ContactInfo::FlagsCache::get_virtual_user_flagcache(
        'user'         => $user,
        'service'      => 'mail',
        'virtual_user' => $email_user,
        'domain'       => $domain,
    );

    for my $key (@$touchfile_fields_ar) {
        $virtual_user_state_obj->set_state( $key, $contact_prefs_hr->{$key} ? 1 : 0 );
    }

    return 1;
}

1;
