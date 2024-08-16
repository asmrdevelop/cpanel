package Cpanel::CustInfo::Model;

# cpanel - Cpanel/CustInfo/Model.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

=head1 NAME

Cpanel::CustInfo::Model - Contains data module generation methods for
the Customer Information properties available in the system and for the
requested user.

=head1 SYNOPSIS

    use Cpanel::CustInfo::Model;

    my $contact_fields = Cpanel::CustInfo::Model::get_contact_fields($is_virtual);

=head1 DESCRIPTION

Contains the model construction. Note that this module uses a global cache.
This optimization came from the original code but interferes with unit testing
so we added the C<clear_cache()> method here to allow callers to force the cache
to be empty.

B<NOTE:> The following functions allow the caller to (inadvertently?) compromise
this module's internals by altering the referred-to hash.

=over 3

=item C<get_all_possible_contact_fields>

=item C<get_active_contact_fields>

=back

B<TODO:> This should probably clone the hash so that the caller can't do that.

=cut

# Do not use in as it will already be loaded if needed
# and it uses lots of memory
#use Cpanel                                          ();
use Cpanel::Validate::Boolean            ();
use Cpanel::Validate::EmailRFC           ();
use Cpanel::Validate::FilesystemNodeName ();
use Cpanel::LoadModule                   ();
use Cpanel::LocaleString                 ();

#----------------------------------------------------------------------

=head1 CONSTANTS

=head2 EMAIL_FIELDS

An ordered list of the contact info fields that pertain to email contact.

=cut

use constant EMAIL_FIELDS => (
    'email',
    'second_email',
);

=head2 FEATURES_TO_EDIT_STRINGS

A list of the features that enable write access to string properties.
Any one of these will enable write access; they do B<NOT> all need to
be enabled.

=cut

use constant FEATURES_TO_EDIT_STRINGS => (
    'updatecontact',
    'updatenotificationprefs',
);

#----------------------------------------------------------------------

# constants
our $SYSTEM_USER  = 0;
our $VIRTUAL_USER = 1;

our @WEBMAIL_FIELDS = (
    EMAIL_FIELDS,
    (
        'notify_account_login',
        'notify_account_login_for_known_netblock',
        'notify_account_login_notification_disabled',
        'pushbullet_access_token',
    ),
);

#These are in descending order of urgency.
my @AUTOSSL_FIELDS = (

    # “FAIL”: total DCV failure, and old cert is “critical”
    'notify_autossl_expiry',

    # “FAIL”: not renewing due to potential SSL coverage loss
    'notify_autossl_expiry_coverage',

    # “FAIL”: not increasing coverage due to potential SSL coverage loss
    'notify_autossl_renewal_coverage',

    # “FAIL”: renewed, but some domains are now non-SSL
    'notify_autossl_renewal_coverage_reduced',

    # “WARN”: installed new, but vhost has domains that cert doesn’t
    'notify_autossl_renewal_uncovered_domains',

    # “SUCCESS”: Great success renewal
    'notify_autossl_renewal',
);

our @FIELD_SORT = (
    'email',
    'second_email',
    'pushbullet_access_token',
    'notify_contact_address_change',
    'notify_contact_address_change_notification_disabled',
    'notify_disk_limit',
    'notify_bandwidth_limit',

    @AUTOSSL_FIELDS,

    'notify_ssl_expiry',
    'notify_email_quota_limit',
    'notify_password_change',
    'notify_password_change_notification_disabled',
    'notify_account_login',
    'notify_account_login_for_known_netblock',
    'notify_account_login_notification_disabled',
    'notify_account_authn_link',
    'notify_account_authn_link_notification_disabled',
    'notify_twofactorauth_change',
    'notify_twofactorauth_change_notification_disabled',
);

my $_cpconf_ref;
my %CONTACT_FIELDS;    # Global cache # TODO: Remove this cache system (LC-4069)

=head1 METHODS

=head2 clear_cache()

Clears the cache.

B<Returns>: Nothing.

=cut

sub clear_cache {
    %CONTACT_FIELDS = ();    # TODO: Remove this cache system (LC-4069)
    undef $_cpconf_ref;
    return;
}

=head2 get_contact_fields($is_virtual)

Fetch all the customer info properties that are usable.

=over 3

=item C<< $is_virtual >> [in, required]

A boolean. If true, request the contact fields for a webmail/virtual user.

=back

B<Returns>: On success, returns a hashref where each name represents a
property stored and the value of that property is a hashref with the
following fields:

=over 3

=item C<< type >> [out]

A string representing the type of property: string or boolean.

=item C<< is_disabler >> [out]

A boolean indicating if this property disables something when truthy.

=item C<< default >> [out]

A boolean or string with the default value for the property if not provided
in the datastore.

=item C<< features >> [out]

An arrayref of the cpanel features required for this property.

=item C<< descp >> [out]

A string representing the description of the property.

=item C<< validator >> [out]

A coderef to a validator method for this property.

=item C<< touchfile >> [out]

A boolean indicating whether to store this property in a state file in
C<$Cpanel::ConfigFiles::USER_NOTIFICATIONS_DIR>.

=item C<< cpuser_key >> [out]

A string representing the field name in the cpanel user config file.

=back

=cut

sub get_contact_fields {
    my ($is_virtual) = @_;

    my $contact_fields;

    if ($is_virtual) {
        $contact_fields = get_active_webmail_contact_fields();
    }
    else {

        # 0 = not a virtual user
        $contact_fields = get_active_contact_fields($SYSTEM_USER);
    }

    return $contact_fields;
}

=head2 get_active_webmail_contact_fields()

Gets the contact fields for webmail/virtual users.

B<Returns>: On success, returns a hashref where each name represents a
property stored and the value of that property is a hashref with the
following fields:

=over 3

=item C<< type >> [out]

A string representing the type of property: string or boolean.

=item C<< is_disabler >> [out]

A boolean indicating if this property disables something when truthy.

=item C<< default >> [out]

A boolean or string with the default value for the property if not provided
in the datastore.

=item C<< features >> [out]

An arrayref of the cpanel features required for this property.

=item C<< descp >> [out]

A string representing the description of the property.

=item C<< validator >> [out]

A coderef to a validator method for this property.

=item C<< touchfile >> [out]

A boolean indicating whether to store this property in a state file in
C<$Cpanel::ConfigFiles::USER_NOTIFICATIONS_DIR>.

=item C<< cpuser_key >> [out]

A string representing the field name in the cpanel user config file.

=back

=cut

sub get_active_webmail_contact_fields {
    clear_cache();    # TODO: Remove this cache system (LC-4069)

    # 1 = a virtual user
    my $obtained_fields = get_active_contact_fields($VIRTUAL_USER);

    my $active_webmail_fields = {
        map { $obtained_fields->{$_} ? ( $_ => $obtained_fields->{$_} ) : () } @WEBMAIL_FIELDS,
    };

    return $active_webmail_fields;
}

=head2 get_active_contact_fields($is_virtual)

Gets the contact fields for cpanel users.

=over 3

=item C<< $is_virtual >> [in, required]

A boolean. If true, request the contact fields for a webmail/virtual user.

=back

B<Returns>: On success, returns a hashref where each name represents a
property stored and the value of that property is a hashref with the
following fields:

=over 3

=item C<< type >> [out]

A string representing the type of property: string or boolean.

=item C<< is_disabler >> [out]

A boolean indicating if this property disables something when truthy.

=item C<< default >> [out]

A boolean or string with the default value for the property if not provided
in the datastore.

=item C<< features >> [out]

An arrayref of the cpanel features required for this property.

=item C<< descp >> [out]

A C<Cpanel::LocalesString> representing the description of the property.

=item C<< validator >> [out]

A coderef to a validator method for this property.

=item C<< touchfile >> [out]

A boolean indicating whether to store this property in a state file in
C<$Cpanel::ConfigFiles::USER_NOTIFICATIONS_DIR>.

=item C<< cpuser_key >> [out]

A string representing the field name in the cpanel user config file.

=back

=cut

sub get_active_contact_fields {
    my ($is_virtual) = @_;
    if ( keys %CONTACT_FIELDS == 0 ) {
        get_all_possible_contact_fields($is_virtual);    # TODO: Remove this cache system (LC-4069)
    }

    Cpanel::LoadModule::load_perl_module('Cpanel::GlobalCache')                             if !$INC{'Cpanel/GlobalCache.pm'};
    Cpanel::LoadModule::load_perl_module('Cpanel::Config::Hulk')                            if !$INC{'Cpanel/Config/Hulk.pm'};
    Cpanel::LoadModule::load_perl_module('Cpanel::BandwidthMgr')                            if !$INC{'Cpanel/BandwidthMgr.pm'};
    Cpanel::LoadModule::load_perl_module('Cpanel::Security::Authn::TwoFactorAuth::Enabled') if !$INC{'Cpanel/Security/Authn/TwoFactorAuth/Enabled.pm'};
    Cpanel::LoadModule::load_perl_module('Cpanel::Config::LoadCpConf')                      if !$INC{'Cpanel/Config/LoadCpConf.pm'};

    $_cpconf_ref ||= Cpanel::Config::LoadCpConf::loadcpconf_not_copy();

    # If there’s no AutoSSL provider configured,
    # then don’t show these fields at all.
    if ( !Cpanel::GlobalCache::data( 'cpanel', 'autossl_current_provider_name' ) ) {
        delete @CONTACT_FIELDS{@AUTOSSL_FIELDS};
    }
    else {

        # Hide any fields that the admin has withheld from users.
        foreach my $field (@AUTOSSL_FIELDS) {
            if ( !Cpanel::GlobalCache::data( 'cpanel', "${field}_user" ) ) {
                delete $CONTACT_FIELDS{$field};
            }
        }
    }

    if ( !$_cpconf_ref->{'notify_expiring_certificates'} ) {
        delete $CONTACT_FIELDS{'notify_ssl_expiry'};
    }
    if ( !Cpanel::Config::Hulk::is_enabled() ) {
        delete @CONTACT_FIELDS{ 'notify_account_login', 'notify_account_login_for_known_netblock', 'notify_account_login_notification_disabled' };
    }
    if ( $_cpconf_ref->{'skipboxcheck'} ) {
        delete $CONTACT_FIELDS{'notify_email_quota_limit'};
    }

    # Removes option from api if “Bandwidth Limit check’ is disabled,
    # or if “Send bandwidth limit notification emails” is disabled in “Tweak Settings”
    if ( !Cpanel::BandwidthMgr::has_at_least_one_bandwidth_limit_notification_enabled() ) {
        delete $CONTACT_FIELDS{'notify_bandwidth_limit'};
    }

    if ( !Cpanel::Security::Authn::TwoFactorAuth::Enabled::is_enabled() ) {
        delete @CONTACT_FIELDS{ 'notify_twofactorauth_change', 'notify_twofactorauth_change_notification_disabled' };
    }

    return \%CONTACT_FIELDS;
}

=head2 get_all_possible_contact_fields($is_virtual)

Returns all of the contact fields even if they are disabled.

=over 3

=item C<< $is_virtual >> [in, required]

A boolean. If true, request the contact fields for a webmail/virtual user.

=back

B<Returns>: On success, returns a hashref where each name represents a
property stored and the value of that property is a hashref with the
following fields:

=over 3

=item C<< type >> [out]

A string representing the type of property: string or boolean.

=item C<< is_disabler >> [out]

A boolean indicating if this property disables something when truthy.

=item C<< default >> [out]

A boolean or string with the default value for the property if not provided
in the datastore.

=item C<< features >> [out]

An arrayref of the cpanel features required for this property.

=item C<< descp >> [out]

A C<Cpanel::LocalesString> representing the description of the property.

=item C<< validator >> [out]

A coderef to a validator method for this property.

=item C<< touchfile >> [out]

A boolean indicating whether to store this property in a state file in
C<$Cpanel::ConfigFiles::USER_NOTIFICATIONS_DIR>.

=item C<< cpuser_key >> [out]

A string representing the field name in the cpanel user config file.

=back

=cut

sub get_all_possible_contact_fields {
    my ($is_virtual) = @_;

    my $can_reset_password = _can_reset_password($is_virtual);

    %CONTACT_FIELDS = (
        'email' => {
            'type'        => 'string',
            'is_disabler' => 0,
            'default'     => '',
            'features'    => [FEATURES_TO_EDIT_STRINGS],
            'descp'       => (
                $can_reset_password
                ? Cpanel::LocaleString->new('Enter an email address to receive account notifications and password reset confirmations.')
                : Cpanel::LocaleString->new('Enter an email address to receive account notifications.')
            ),
            'validator'  => \&_valid_email_field,
            'touchfile'  => 0,
            'cpuser_key' => 'CONTACTEMAIL',
        },
        'second_email' => {
            'type'        => 'string',
            'is_disabler' => 0,
            'default'     => '',
            'features'    => [FEATURES_TO_EDIT_STRINGS],
            'descp'       => (
                $can_reset_password
                ? Cpanel::LocaleString->new('Enter a second email address to receive account notifications and password reset confirmations.')
                : Cpanel::LocaleString->new('Enter a second email address to receive account notifications.')
            ),
            'validator'  => \&_valid_email_field,
            'touchfile'  => 0,
            'cpuser_key' => 'CONTACTEMAIL2',
        },
        'pushbullet_access_token' => {
            'type'        => 'string',
            'is_disabler' => 0,
            'default'     => '',
            'features'    => [FEATURES_TO_EDIT_STRINGS],
            'descp'       => Cpanel::LocaleString->new('An access token for Pushbullet.'),
            'validator'   => sub {
                return 0 if !length( $_[0] );
                return Cpanel::Validate::FilesystemNodeName::is_valid( $_[0] );
            },
            'touchfile'  => 0,
            'cpuser_key' => 'PUSHBULLET_ACCESS_TOKEN',
        },
        'notify_disk_limit' => {
            'type'        => 'boolean',
            'is_disabler' => 0,
            'default'     => _default_notification_status(),
            'features'    => ['updatenotificationprefs'],
            'descp'       => Cpanel::LocaleString->new('My account approaches its disk quota.'),
            'validator'   => \&Cpanel::Validate::Boolean::is_valid,
            'touchfile'   => 0,
            'cpuser_key'  => 'notify_disk_limit',
        },
        'notify_bandwidth_limit' => {
            'type'        => 'boolean',
            'is_disabler' => 0,
            'default'     => _default_notification_status(),
            'features'    => ['updatenotificationprefs'],
            'descp'       => Cpanel::LocaleString->new('My account approaches its bandwidth usage limit.'),
            'validator'   => \&Cpanel::Validate::Boolean::is_valid,
            'touchfile'   => 0,
            'cpuser_key'  => 'notify_bandwidth_limit',
        },
        'notify_email_quota_limit' => {
            'type'        => 'boolean',
            'is_disabler' => 0,
            'default'     => _default_notification_status(),
            'features'    => ['updatenotificationprefs'],
            'descp'       => Cpanel::LocaleString->new('Any of my account’s email accounts approaches or is over quota.'),
            'validator'   => \&Cpanel::Validate::Boolean::is_valid,
            'touchfile'   => 0,
            'cpuser_key'  => 'notify_email_quota_limit',
        },
        'notify_password_change' => {
            'type'        => 'boolean',
            'is_disabler' => 0,
            'default'     => _default_notification_status(),
            'features'    => ['updatenotificationprefs'],
            'descp'       => Cpanel::LocaleString->new('My account’s password changes.'),
            'validator'   => \&Cpanel::Validate::Boolean::is_valid,
            'touchfile'   => 0,
            'cpuser_key'  => 'notify_password_change',
            'infotext'    => Cpanel::LocaleString->new('The system will notify you when the password changes because of a user request.'),
        },
        'notify_account_login' => {
            'type'        => 'boolean',
            'is_disabler' => 0,
            'default'     => 0,
            'features'    => ['updatenotificationprefs'],
            'descp'       => Cpanel::LocaleString->new('Someone logs in to my account.'),
            'validator'   => \&Cpanel::Validate::Boolean::is_valid,
            'touchfile'   => 1,
            'cpuser_key'  => 'notify_account_login',
        },
        'notify_contact_address_change' => {
            'type'        => 'boolean',
            'is_disabler' => 0,
            'default'     => _default_notification_status(),
            'features'    => ['updatenotificationprefs'],
            'descp'       => Cpanel::LocaleString->new('My contact email address changes.'),
            'validator'   => \&Cpanel::Validate::Boolean::is_valid,
            'touchfile'   => 0,
            'cpuser_key'  => 'notify_contact_address_change',
            'infotext'    => Cpanel::LocaleString->new("The system will notify you at your current and previous contact email addresses."),
        },
        'notify_account_authn_link' => {
            'type'        => 'boolean',
            'is_disabler' => 0,
            'default'     => _default_notification_status(),
            'features'    => ['updatenotificationprefs'],
            'descp'       => Cpanel::LocaleString->new('An external account links to my account for authentication.'),
            'validator'   => \&Cpanel::Validate::Boolean::is_valid,
            'touchfile'   => 0,
            'cpuser_key'  => 'notify_account_authn_link',
        },
        'notify_twofactorauth_change' => {
            'type'        => 'boolean',
            'is_disabler' => 0,
            'default'     => _default_notification_status(),
            'features'    => ['updatenotificationprefs'],
            'descp'       => Cpanel::LocaleString->new('My account’s two-factor authentication configuration changes.'),
            'validator'   => \&Cpanel::Validate::Boolean::is_valid,
            'touchfile'   => 0,
            'cpuser_key'  => 'notify_twofactorauth_change',
        },
        'notify_account_login_for_known_netblock' => {
            'type'           => 'boolean',
            'is_disabler'    => 0,
            'default'        => 0,
            'features'       => ['updatenotificationprefs'],
            'descp'          => Cpanel::LocaleString->new('Send login notifications, even when the user logs in from an IP address range or netblock that contains an IP address from which a user successfully logged in previously.'),
            'validator'      => \&Cpanel::Validate::Boolean::is_valid,
            'touchfile'      => 1,
            'cpuser_key'     => 'notify_account_login_for_known_netblock',
            'onchangeparent' => 'notify_account_login',
        },
        'notify_password_change_notification_disabled' => {
            'type'           => 'boolean',
            'is_disabler'    => 1,
            'default'        => _default_notification_status(),
            'features'       => ['updatenotificationprefs'],
            'descp'          => Cpanel::LocaleString->new('My preference for account password change notifications is disabled.'),
            'validator'      => \&Cpanel::Validate::Boolean::is_valid,
            'touchfile'      => 0,
            'cpuser_key'     => 'notify_password_change_notification_disabled',
            'onchangeparent' => 'notify_password_change',
        },
        'notify_account_login_notification_disabled' => {
            'type'           => 'boolean',
            'is_disabler'    => 1,
            'default'        => _default_notification_status(),
            'features'       => ['updatenotificationprefs'],
            'descp'          => Cpanel::LocaleString->new('My preference for successful login notifications is disabled.'),
            'validator'      => \&Cpanel::Validate::Boolean::is_valid,
            'touchfile'      => 0,
            'cpuser_key'     => 'notify_account_login_notification_disabled',
            'onchangeparent' => 'notify_account_login',
        },
        'notify_contact_address_change_notification_disabled' => {
            'type'           => 'boolean',
            'is_disabler'    => 1,
            'default'        => _default_notification_status(),
            'features'       => ['updatenotificationprefs'],
            'descp'          => Cpanel::LocaleString->new('My preference for contact email address change notifications is disabled.'),
            'validator'      => \&Cpanel::Validate::Boolean::is_valid,
            'touchfile'      => 0,
            'cpuser_key'     => 'notify_contact_address_change_notification_disabled',
            'onchangeparent' => 'notify_contact_address_change',
        },
        'notify_account_authn_link_notification_disabled' => {
            'type'           => 'boolean',
            'is_disabler'    => 1,
            'default'        => _default_notification_status(),
            'features'       => ['updatenotificationprefs'],
            'descp'          => Cpanel::LocaleString->new('My preference for external account link notifications is disabled.'),
            'validator'      => \&Cpanel::Validate::Boolean::is_valid,
            'touchfile'      => 0,
            'cpuser_key'     => 'notify_account_authn_link_notification_disabled',
            'onchangeparent' => 'notify_account_authn_link',
        },
        'notify_twofactorauth_change_notification_disabled' => {
            'type'           => 'boolean',
            'is_disabler'    => 1,
            'default'        => _default_notification_status(),
            'features'       => ['updatenotificationprefs'],
            'descp'          => Cpanel::LocaleString->new('My preference for two-factor authentication notifications is disabled.'),
            'validator'      => \&Cpanel::Validate::Boolean::is_valid,
            'touchfile'      => 0,
            'cpuser_key'     => 'notify_twofactorauth_change_notification_disabled',
            'onchangeparent' => 'notify_twofactorauth_change',
        },
        'notify_autossl_renewal' => {
            'type'           => 'boolean',
            'is_disabler'    => 0,
            'default'        => _default_notification_status(),
            'features'       => ['autossl'],
            'descp'          => Cpanel::LocaleString->new('[asis,AutoSSL] has installed a certificate successfully.'),
            'validator'      => \&Cpanel::Validate::Boolean::is_valid,
            'touchfile'      => 0,
            'cpuser_key'     => 'notify_autossl_renewal',
            'onchangeparent' => 'autossl',
        },
        'notify_autossl_expiry_coverage' => {
            'type'           => 'boolean',
            'is_disabler'    => 0,
            'default'        => _default_notification_status(),
            'features'       => ['autossl'],
            'descp'          => Cpanel::LocaleString->new('[asis,AutoSSL] defers certificate renewal because a domain on the current certificate has failed [output,abbr,DCV,Domain Control Validation]. The system only sends this notification when a certificate is in the latter half of its renewal period.'),
            'validator'      => \&Cpanel::Validate::Boolean::is_valid,
            'touchfile'      => 0,
            'cpuser_key'     => 'notify_autossl_expiry_coverage',
            'onchangeparent' => 'autossl',
        },
        'notify_autossl_renewal_coverage' => {
            'type'           => 'boolean',
            'is_disabler'    => 0,
            'default'        => _default_notification_status(),
            'features'       => ['autossl'],
            'descp'          => Cpanel::LocaleString->new('[asis,AutoSSL] will not secure a new domain because a domain on the current certificate has failed [output,abbr,DCV,Domain Control Validation]. The system only sends this notification when a certificate is not yet in the latter half of its renewal period.'),
            'validator'      => \&Cpanel::Validate::Boolean::is_valid,
            'touchfile'      => 0,
            'cpuser_key'     => 'notify_autossl_renewal_coverage',
            'onchangeparent' => 'autossl',
        },
        'notify_autossl_renewal_coverage_reduced' => {
            'type'           => 'boolean',
            'is_disabler'    => 0,
            'default'        => _default_notification_status(),
            'features'       => ['autossl'],
            'descp'          => Cpanel::LocaleString->new('[asis,AutoSSL] has renewed a certificate, but the new certificate lacks at least one domain that the previous certificate secured.'),
            'validator'      => \&Cpanel::Validate::Boolean::is_valid,
            'touchfile'      => 0,
            'cpuser_key'     => 'notify_autossl_renewal_coverage_reduced',
            'onchangeparent' => 'autossl',
        },
        'notify_autossl_renewal_uncovered_domains' => {
            'type'           => 'boolean',
            'is_disabler'    => 0,
            'default'        => _default_notification_status(),
            'features'       => ['autossl'],
            'descp'          => Cpanel::LocaleString->new('[asis,AutoSSL] has renewed a certificate, but the new certificate lacks one or more of the website’s domains.'),
            'validator'      => \&Cpanel::Validate::Boolean::is_valid,
            'touchfile'      => 0,
            'cpuser_key'     => 'notify_autossl_renewal_uncovered_domains',
            'onchangeparent' => 'autossl',
        },
        'notify_autossl_expiry' => {
            'type'           => 'boolean',
            'is_disabler'    => 0,
            'default'        => _default_notification_status(),
            'features'       => ['autossl'],
            'descp'          => Cpanel::LocaleString->new('[asis,AutoSSL] cannot request a certificate because all of the domains on the website have failed [output,abbr,DCV,Domain Control Validation].'),
            'validator'      => \&Cpanel::Validate::Boolean::is_valid,
            'touchfile'      => 0,
            'cpuser_key'     => 'notify_autossl_expiry',
            'onchangeparent' => 'autossl',
        },
        'notify_ssl_expiry' => {
            'type'        => 'boolean',
            'is_disabler' => 0,
            'default'     => _default_notification_status(),
            'features'    => ['updatenotificationprefs'],
            'descp'       => Cpanel::LocaleString->new('[asis,SSL] certificate expiry.'),
            'validator'   => \&Cpanel::Validate::Boolean::is_valid,
            'touchfile'   => 0,
            'cpuser_key'  => 'notify_ssl_expiry',
            'infotext'    => Cpanel::LocaleString->new("The system will notify you if a non-[asis,AutoSSL] certificate will expire soon."),
        },

    );

    return \%CONTACT_FIELDS;
}

sub _valid_email_field {

    # We need to accept empty string and undef here, as they're essential for
    # clearing the address.
    return 0 if !defined $_[0];
    return 1 if !length $_[0];
    return 1 if Cpanel::Validate::EmailRFC::is_valid( $_[0] );
    return 0;
}

sub _can_reset_password {
    my ($is_virtual) = @_;
    return ( $is_virtual ? $Cpanel::CONF{'resetpass_sub'} : $Cpanel::CONF{'resetpass'} );
}

{
    my $_cache;    # could use state variable

    sub _default_notification_status {
        return $_cache if defined $_cache;
        require Cpanel::Logger;
        $_cache = Cpanel::Logger::is_sandbox() ? 0 : 1;
        return $_cache;
    }
}

1;
