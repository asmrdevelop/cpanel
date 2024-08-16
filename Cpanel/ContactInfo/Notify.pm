package Cpanel::ContactInfo::Notify;

# cpanel - Cpanel/ContactInfo/Notify.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# our for testing
our $NOTIFY_ON_CHANGE  = 1;
our $NOTIFY_ON_DISABLE = 2;

###########################################################################
#
# Method:
#   get_notification_preference_from_contact_data
#
# Description:
#   This function examines a user's CPUSER/contactinfo data and extracts information on when to
#   contact a user when a notification setting has changed.
#
# Parameters:
#   $contactinfo_data_hr - A hashref representing the CPUSER/contactinfo data for a user. The notification preferences
#      will be derived from this data.
#
# Exceptions:
#   None currently.
#
# Returns:
#   The method returns a hashref with the following format:
#      {
#         'contactinfo_data_hr' => 'setting'
#      }
#   Where setting can be:
#      $NOTIFY_ON_CHANGE  => Notify the user if the notification setting corresponding with the key has been disabled
#      $NOTIFY_ON_DISABLE => Notify the user if the notification setting corresponding with the key has changed from the previous setting
#
#   If a key does not appear in the hash, then do not notify the user if that setting is disabled or changed.
#
sub get_notification_preference_from_contact_data {
    my ($contactinfo_data_hr) = @_;

    my %contact_prefs = ();

    if ( $contactinfo_data_hr->{'notify_contact_address_change'} ) {

        # these will have their messages set during notification
        $contact_prefs{'CONTACTEMAIL'}  = $NOTIFY_ON_CHANGE;
        $contact_prefs{'CONTACTEMAIL2'} = $NOTIFY_ON_CHANGE;
    }

    my %disable_guards = (
        'notify_password_change_notification_disabled'        => 'notify_password_change',
        'notify_account_login_notification_disabled'          => 'notify_account_login',
        'notify_contact_address_change_notification_disabled' => 'notify_contact_address_change',
        'notify_account_authn_link_notification_disabled'     => 'notify_account_authn_link',
        'notify_twofactorauth_change_notification_disabled'   => 'notify_twofactorauth_change',
    );

    for my $guard_key_name ( keys %disable_guards ) {
        if ( $contactinfo_data_hr->{$guard_key_name} ) {
            $contact_prefs{ $disable_guards{$guard_key_name} } = $NOTIFY_ON_DISABLE;

            # Otherwise, someone could just disable this notification with one save,
            # then disable the password change notification
            $contact_prefs{$guard_key_name} = $NOTIFY_ON_DISABLE;
        }
    }

    return \%contact_prefs;
}

###########################################################################
#
# Method:
#   get_notification_delta
#
# Description:
#   This function checks to see if a specified key in a user's CPUSER/contactinfo data has changed.
#   If the user requested to be notified if that CPUSER/contactinfo key changed, the function will
#   return information about the necessary notification to send the user about said change.
#
# Parameters (accepts a hash of OPTS):
#   $key_notification_preference  - A enumeration integer value indicating the user's notification preference for
#                                   the supplied value, it can either be $NOTIFY_ON_CHANGE or $NOTIFY_ON_DISABLE.
#   $current_value                - The current/unmodified value for the CPUSER/contactinfo data key.
#   $new_value                    - The new/modified value for the CPUSER/contactinfo data key.
#
# Exceptions:
#   None currently.
#
# Returns:
#   If the CPUSER/contactinfo data value has not changed or if the user has not requested to be notified of the change,
#   this function will return nothing. If the value of the key HAS changed and the user HAS requested to be
#   notified, then the method returns a hashref with the following format:
#      {
#         'preference'    => The notification preference of the user for the passed in CPUSER/contactinfo key,
#                            it can either be $NOTIFY_ON_CHANGE or $NOTIFY_ON_DISABLE
#         'current_value' => The current/unmodified value of the CPUSER/contactinfo data key, aka what the key is changing from.
#         'new_value'     => The new/modified value of the CPUSER/contactinfo data key, aka what the key will be changing to.
#      }
#
sub get_notification_delta {
    my (%OPTS) = @_;

    my ( $key_notification_preference, $current_value, $new_value ) = @OPTS{qw( key_notification_preference current_value new_value )};

    return if !defined $key_notification_preference;

    return if ( !$current_value && !$new_value );

    my $notify_user = 0;
    if ( $current_value && !$new_value ) {
        if ( $key_notification_preference == $NOTIFY_ON_CHANGE || $key_notification_preference == $NOTIFY_ON_DISABLE ) {
            $notify_user = 1;
        }
    }
    elsif ( !$current_value && $new_value || $current_value ne $new_value ) {
        if ( $key_notification_preference == $NOTIFY_ON_CHANGE ) {
            $notify_user = 1;
        }
    }

    if ($notify_user) {
        return {
            'preference'    => $key_notification_preference,
            'current_value' => defined $current_value ? $current_value : q{},
            'new_value'     => defined $new_value     ? $new_value     : q{},
        };
    }

    return;
}

# this list currently supports the needs for both cPanel users and mail users as the
# notifications_hr only contains keys applicable to the user's context. And it happens that
# the mail user's possible notifications is a subset of the cPanel user's.
my @keys_to_tell_the_notice_object_about = qw(
  notify_account_login
  notify_account_login_notification_disabled
  notify_contact_address_change
  notify_contact_address_change_notification_disabled
  notify_password_change
  notify_password_change_notification_disabled
  notify_account_authn_link
  notify_account_authn_link_notification_disabled
  notify_twofactorauth_change
  notify_twofactorauth_change_notification_disabled
);

###########################################################################
#
# Method:
#   send_contactinfo_change_notifications_to_user
#
# Description:
#   This function checks to see if a specified key in a user's CPUSER/contactinfo data has changed.
#   If the user requested to be notified if that CPUSER/contactinfo key changed, the function will
#   return information about the necessary notification to send the user about said change.
#
# Parameters (accepts a hash of OPTS):
#   to_user          - The account name or virtual account name of the user that's contactinfo changed.
#                       Examples: bob (cPanel user), someone@bobsdomains.org (Webmail user)
#   username         - The cPanel account name. It may be the same as to_user if the message is about the cPanel account.
#                       Examples: bob, nick, frank (no webmail users here)
#   origin           - The interface where the action that caused this notification occurred (cpanel, webmail, etc).
#   ip               - The human readable IP address of the connection that initiated the action that caused this
#                      notification to occur.
#   notifications_hr - A hashref consisting of notification deltas mapped by field name.
#
# Exceptions:
#   In all the ways Cpanel::iContact::Class::ContactInfo::Change->new will throw exceptions.
#
# Returns:
#   Returns 1 or dies;
#
sub send_contactinfo_change_notifications_to_user {
    my (%OPTS) = @_;

    my ( $to_user, $username, $origin, $ip, $notifications_hr ) = @OPTS{qw( to_user username origin ip notifications_hr )};

    my %email_updates = ();
    for my $email_cpuser_key (qw( CONTACTEMAIL CONTACTEMAIL2 )) {
        next if !$notifications_hr->{$email_cpuser_key};

        my $email_type   = $email_cpuser_key eq 'CONTACTEMAIL' ? 'primary' : 'secondary';
        my $email_change = delete $notifications_hr->{$email_cpuser_key};
        my ( $old_email, $new_email ) = @{$email_change}{qw(current_value new_value)};

        $email_updates{$email_type} = [ $old_email, $new_email ];
    }
    require Cpanel::Notify;
    Cpanel::Notify::notification_class(
        'class'            => 'ContactInfo::Change',
        'application'      => 'ContactInfo::Change',
        'constructor_args' => [
            username                          => $username,
            to                                => $to_user,
            user                              => $to_user,
            notification_targets_user_account => ( $username ne 'root' ? 1 : 0 ),
            extra_addresses_to_notify         => $notifications_hr->{'cpuser_emails'} || [],
            source_ip_address                 => $ip,
            updated_email_addresses           => \%email_updates,
            origin                            => $origin,
            disabled_notifications            => [ grep { $notifications_hr->{$_} } @keys_to_tell_the_notice_object_about ],
            team_account                      => defined $ENV{'TEAM_USER'} ? 1 : 0,
        ]
    );

    return 1;
}

1;
