package Cpanel::API::Variables;

# cpanel - Cpanel/API/Variables.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception ();
use Cpanel::Imports;

use constant SESSION_INFO_RETURNS => { host => 'host' };

use constant SERVER_INFO_RETURNS => {
    RS                                => 'default_theme',
    VFILTERDIR                        => 'email_filter_storage_directory',
    allowparkhostnamedomainsubdomains => 'allow_park_subdomain_on_hostname',
    allowremotedomains                => 'allow_remote_domains',
    allowunregistereddomains          => 'allow_unregistered_domains',
    apache_port                       => 'apache_port',
    apache_ssl_port                   => 'apache_ssl_port',
    api_shell                         => 'api_shell',
    awstatsbrowserupdate              => 'awstats_browser_update',
    awstatsreversedns                 => 'awstats_reverse_dns',
    cpanel_root_directory             => 'cpanel_root_directory',
    database_prefix                   => 'database_prefix_required',
    display_cpanel_doclinks           => 'display_cpanel_doclinks',
    dnsadminapp                       => 'dnsadmin_app',
    empty_trash_days                  => 'empty_trash_days',
    enablefileprotect                 => 'enable_file_protect',
    file_upload_max_bytes             => 'file_upload_maximum_bytes',
    file_upload_must_leave_bytes      => 'file_upload_must_leave_bytes',
    file_usage                        => 'file_usage',
    ftpserver                         => 'ftp_server',
    htaccess_check_recurse            => 'htaccess_check_recurse',
    invite_sub                        => 'invite_sub',
    ipv6_listen                       => 'ipv6_listen',
    local_nameserver_type             => 'local_nameserver_type',
    logout_redirect_url               => 'logout_redirect_url',
    mailbox_storage_format            => 'mailbox_storage_format',
    mailserver                        => 'mail_server',
    minpwstrength                     => 'minimum_password_strength',
    minpwstrength_mysql               => 'minimum_password_strength_mysql',
    'mysql-host'                      => 'mysql_host',
    'mysql-version'                   => 'mysql_version',
    php_max_execution_time            => 'php_maximum_execution_time',
    php_memory_limit                  => 'php_memory_limit',
    php_post_max_size                 => 'php_post_maximum_size',
    php_system_default_version        => 'php_system_default_version',
    php_upload_max_filesize           => 'php_upload_maximum_filesize',
    phploader                         => 'php_loader',
    phpopenbasedirhome                => 'php_open_basedir_home',
    pma_disableis                     => 'phpmyadmin_disable_search_info_schema',
    publichtmlsubsonly                => 'docroots_in_public_html_only',
    requiressl                        => 'require_ssl',
    resetpass                         => 'allow_reset_password',
    resetpass_sub                     => 'allow_reset_password_for_subaccounts',
    skipanalog                        => 'disable_analog',
    skipapacheclientsoptimizer        => 'skip_apache_clients_optimizer',
    skipawstats                       => 'disable_awstats',
    skipboxcheck                      => 'skip_mailbox_warnings_check',
    skipboxtrapper                    => 'disable_boxtrapper',
    skipbwlimitcheck                  => 'skip_bandwidth_limit_check',
    skipmailman                       => 'disable_mailman',
    skiproundcube                     => 'disable_roundcube',
    skipspamassassin                  => 'disable_spamassassin',
    skipspambox                       => 'disable_spambox',
    skipwebalizer                     => 'disable_webalizer',
    ssl_default_key_type              => 'ssl_default_key_type',
    use_information_schema            => 'use_information_schema',
    usemailformailmanurl              => 'use_mail_for_mailman_url',
    userdirprotect                    => 'is_mod_userdir_enabled',
    version                           => 'version',
};

use constant USER_INFO_TRANSFORMS => {
    _PACKAGE_EXTENSIONS       => 'package_extensions',
    BACKUP                    => 'backup_enabled',
    BWLIMIT                   => 'bandwidth_limit',
    CONTACTEMAIL              => 'contact_email',
    CONTACTEMAIL2             => 'contact_email_2',
    DBOWNER                   => 'database_owner',
    DEADDOMAINS               => 'dead_domains',
    DEMO                      => 'demo_mode',
    FEATURELIST               => 'feature_list',
    HASCGI                    => 'cgi_enabled',
    HASDKIM                   => 'dkim_enabled',
    HASSPF                    => 'spf_enabled',
    HOMEDIRLINKS              => 'home_directory_links',
    LEGACY_BACKUP             => 'legacy_backup_enabled',
    MAXADDON                  => 'maximum_addon_domains',
    MAXFTP                    => 'maximum_ftp_accounts',
    MAXLST                    => 'maximum_mailing_lists',
    MAXPARK                   => 'maximum_parked_domains',
    MAXPOP                    => 'maximum_mail_accounts',
    MAXSQL                    => 'maximum_databases',
    MAXSUB                    => 'maximum_subdomains',
    MAX_DEFER_FAIL_PERCENTAGE => 'maximum_defer_fail_percentage',
    MAX_EMAILACCT_QUOTA       => 'maximum_email_account_disk_quota',
    MAX_EMAIL_PER_HOUR        => 'maximum_emails_per_hour',
    MAXPASSENGERAPPS          => 'maximum_passenger_apps',
    MTIME                     => 'last_modified',
    RS                        => 'theme',
    STARTDATE                 => 'created',
    SSL_DEFAULT_KEY_TYPE      => 'ssl_default_key_type',
    UTF8MAILBOX               => 'utf8_mailbox',
};

use constant USER_INFO_BLACKLIST => [
    '__CACHE_DATA_VERSION',
    'DNS',
    'name',
    'pass',
    'WORKER_NODE-Mail',
];

my $non_mutating = {
    allow_demo => 1,
};

our %API = (
    get_user_information    => $non_mutating,
    get_session_information => $non_mutating,
    get_server_information  => $non_mutating,
);

=head1 MODULE

C<Cpanel::API::Variables>

=head1 DESCRIPTION

C<Cpanel::API::Variables> provides quick access to common user and server configuration data.

These methods for the most part use data loaded from one of the various configuration files.

=head1 FUNCTIONS

=head2 get_user_information()

Get common user infomation. This includes the data from the current user's
configuration file and some other data about the user.

=head3 ARGUMENTS

=over

=item name - string [ Supports multiple ]

Optional, name of one or more variable sets to retrieve. If not provided, the method will
return all the properties available.

=back

=head3 RETURNS

=over 1

=item backup_enabled : Boolean

Whether the user has backups enabled.

=item bandwidth_limit : numeric|unlimited

The account's bandwidth limit in MB.

=item cgi_enabled : Boolean

Whether CGI is enabled.

=item contact_email : string

The account's contact email address.

=item contact_email_2 : string

The account's alternate contact email address, if one exists.

=item cpanel_root_directory : string

System path to cPanel core installation directory.

=item created : integer

The account's creation date.

=item created_in_version : string

The version of the software in use when the account was created.

=item database_owner : string

The owner of the databases on the account.

=item dead_domains : string[]

The account's inactive domains.

=item demo_mode : Boolean

Whether demo mode is enabled.

=item disk_block_limit : integer

The number of disk blocks for the account, kilobytes.

=item dkim_enabled : Boolean

Whether DKIM is enabled.

=item domain : string

The cPanel account's main domain.

=item domains : string[]

A list of the account's domains and subdomains.

=item feature : hash

A hash containing features that are enabled or disabled

=item feature_list : string

The name of the cPanel account's feature list.

=item gid : integer

The account's group ID.

=item home : string

The user's home directory.

=item home_directory_links : string[]

Any symlinks to the cPanel account's home directory.

=item ip : string

The account's IPv4 address.

=item lang : string

The account's default language.

=item last_modified : integer

The time that the user's configuration file was last modified.

=item legacy_backup_enabled : Boolean

Whether legacy backups are enabled.

=item locale : string

The account's default locale.

=item mailbox_format : string

The storage format that the account's mailboxes use.

=item maximum_addon_domains : integer|unlimited

The account's maximum number of addon domains.

=item maximum_databases : integer|unlimited

The account's maximum number of SQL databases.

=item maximum_defer_fail_percentage : integer|unlimited

The percentage of failed or deferred email messages that the account can send per hour before outgoing mail is rate-limited.

=item maximum_email_account_disk_quota : integer|unlimited

The maximum size, in Megabytes (MB), that the account can define when it creates an email account.

=item maximum_email_per_hour : integer|unlimited

The maximum number of emails that the account can send in one hour.

=item maximum_ftp_accounts : integer|unlimited

The account's maximum number of FTP accounts.

=item maximum_mail_accounts : integer

The maximum number of email accounts for the account.

=item maximum_mailing_lists : integer|unlimited

The account's maximum number of mailing lists.

=item maximum_parked_domains : integer|unlimited

The account's maximum number of aliases.

=item maximum_passenger_apps : integer|unlimited

The account's maximum number of Passenger applications.

=item maximum_subdomains : integer|unlimited

The account's maximum number of subdomains.

=item mxcheck : hash

A hash of domains and how they receive mail. local|remote|secondary

###### ALL THE NOTIFY ###############

=item notify_account_authn_link : Boolean

Whether to send a notification when the user enables External Authentication.

=item notify_account_authn_link_notification_disabled : Boolean

Whether to send a notification when the notify_account_authn_link parameter changed

=item notify_account_login : Boolean

Whether to send a notification when the user logs in to their account.

=item notify_account_login_for_known_netblock : Boolean

Whether to send a notification when the user logs in to their account, regardless of the user's previously known IP address history.

=item notify_account_login_notification_disabled : Boolean

Whether to send a notification when the notify_account_login is changed

=item notify_autossl_expiry : Boolean

Whether to send a notification upon AutoSSL certificate expiry.

=item notify_autossl_expiry_coverage : Boolean

Whether to send a notification when AutoSSL cannot renew a certificate because domains that fail Domain Control Validation (DCV) exist on the current certificate.

=item notify_autossl_renewal_coverage : Boolean

Whether the system sends a notification when AutoSSL renews a certificate.

=item notify_autossl_renewal_coverage_reduced : Boolean

Whether to send a notification when AutoSSL renews a certificate, but the new certificate lacks at least one domain that the previous certificate secured.

=item notify_autossl_renewal_uncovered_domains : Boolean

Whether to send a notification when AutoSSL has renewed a certificate, but the new certificate lacks one or more of the website's domains.

=item notify_bandwidth_limit : Boolean

Whether to send a notification when the user approaches their bandwidth limit.

=item notify_contact_address_change : Boolean

Whether to send a notification when the contact address changes.

=item notify_contact_address_change_notification_disabled : Boolean

Whether to send a notification when the notify_contact_address_change parameter is changed.

=item notify_disk_limit : Boolean

Whether to send a notification when the user approaches their disk quota.

=item notify_password_change

Whether to send a notification when the user changes their password.

=item notify_password_change_notification_disabled : Boolean

Whether to send a notification when the notify_password_change_notification_disabled parameter is changed.

=item notify_twofactorauth_change : Boolean

Whether to send a notification when the user's Two-Factor Authentication for WHM configuration changes.

=item notify_twofactorauth_change_notification_disabled : Boolean

Whether to send a notification when the notify_twofactorauth_change parameter is changed.

=item owner : string

The cPanel account's owner.

=item package_extensions : arrayref of string

The account's package extensions.

=item plan : string

The account's hosting package.

=item pushbullet_access_token : string

The account's Pushbullet access token.

=item shell : string

The account's shell.

=item spf_enabled : Boolean

Whether SPF is enabled.

=item theme : string

The path to the account's cPanel interface and Webmail theme files, relative to the home directory.

=item uid : string

The account's user ID on the system.

=item user : string

The account's current username.

=item utf8_mailbox : Boolean

Whether UTF-8-encoded mailbox names are enabled for the cPanel account.

=back

=head3 THROWS

=over

=item When you request a variable the does not exist.

=back

=head3 EXAMPLES

=head4 Command line usage

    uapi --user=cpuser --output=jsonpretty Variables get_user_information name=home

The returned data will contain a structure similar to the JSON below:

    "data" : {
        "home" : "/home/tommy"
    },

=head4 Template Toolkit

Fetch all the variables available.

    [%
    USE Dumper;
    SET result = execute('Variables', 'get_user_information', {});
    IF result.status;
        Dumper.dump(result.data);
    END;
    %]

Fetch one specific variable.

    [%
    SET result = execute('Variables', 'get_user_information', { name => 'home' });
    IF result.status %]
    Home Directory: [% result.data.home %]
    [% END %]

Fetch multiple specific variables.

    [%
    SET result = execute('Variables', 'get_user_information', { name-1 => 'home', name-2 => 'domains' });
    IF result.status %]
    Home Directory:    [% result.data.home %]
    Number Of Domains: [% result.data.domains.size %]
    [% END %]

=cut

sub get_user_information {
    my ( $args, $result ) = @_;

    my @wanted    = $args->get_multiple('name');
    my $variables = {
        %Cpanel::CPDATA,
        %Cpanel::USERDATA,
        cpanel_root_directory => $Cpanel::CONF{root},
    };

    my $returns = _transform_results( $variables, USER_INFO_TRANSFORMS(), USER_INFO_BLACKLIST(), @wanted );
    $result->data($returns);

    return 1;
}

=head2 get_server_information()

=head3 ARGUMENTS

=over

=item name - string [ Supports multiple ]

Optional, name of one or more variable sets to retrieve. If not provided, the method will
return all the properties available.

=back

=head3 RETURNS

A hashref with various properties depending on what names you request.

These available properties are the ones in the global cPanel configuration settings.

See: https://go.cpanel.net/ThecpanelconfigFile

=head3 THROWS

=over

=item When you request a variable that does not exist.

=back

=head3 EXAMPLES

=head4 Command line usage

    uapi --user=cpuser --output=jsonpretty Variables get_server_information

Returns a structure with at most all of the keys defined in SERVER_INFO_RETURNS

=head4 Template Toolkit

    [%
    SET result = execute('Variables', 'get_server_information', {});
    IF result.status %]
    cPanel is installed in: [% result.data.cpanel_root_directory %]
    [% END %]

=cut

sub get_server_information {
    my ( $args, $result ) = @_;
    my @wanted = $args->get_multiple('name');

    my $variables = {
        %Cpanel::CONF,
        cpanel_root_directory => $Cpanel::CONF{root},
    };

    my $returns = _build_results( $variables, SERVER_INFO_RETURNS(), @wanted );
    $result->data($returns);

    return 1;
}

=head2 get_session_information()

Gets some of the web server environment variables.

B<WARNING>: Session information is only available if the request if made from a web page since the values here are retrieved from the active web server. Calling this API from the command line will not get meaningful data.

=head3 ARGUMENTS

=over

=item name - string [ Supports multiple ]

Optional, name of one or more variable sets to retrieve. If not provided, the method will
return all the properties available.

=back

=head3 RETURNS

=over

=item host - string

The value in the ENV{HTTP_HOST} server variable. Only applicable is the API is called via the web interface.

=back

=head3 THROWS

=over

=item When you request a variable that does not exist.

=back

=head3 EXAMPLES

=head4 Command line usage

    uapi --user=cpuser --output=jsonpretty Variables get_session_information

The returned data will contain a structure similar to the JSON below:

    "data" : {
        "host" : "server1.com"
    }

=head4 Template Toolkit

    [%
    SET result = execute('Variables', 'get_session_information', {});
    IF result.status %]
    Host: [% result.data.host %]
    [% END %]

=cut

sub get_session_information {
    my ( $args, $result ) = @_;

    if ( !exists( $ENV{"SERVER_SOFTWARE"} ) || index( $ENV{'SERVER_SOFTWARE'}, 'cpsrvd' ) == -1 ) {
        $result->raw_warning( locale->maketext("This API is only valid when called via a web interface.") );
    }
    my $variables = {
        host => $Cpanel::httphost,
    };
    my @wanted  = $args->get_multiple('name');
    my $returns = _build_results( $variables, SESSION_INFO_RETURNS(), @wanted );
    $result->data($returns);

    return 1;
}

=head2 _throw_invalid_param(NAMES, VALIDS) [PRIVATE]

Throw an InvalidParameter exception with the provided names

=head3 ARGUMENTS

=over

=item NAMES - array of strings

Requested variable names to return.

=item VALIDS - array of strings

A full list of valid parameters.

=back

=cut

sub _throw_invalid_param {
    my ( $names, $valids ) = @_;
    die Cpanel::Exception::create(
        'InvalidParameter',
        'The [asis,name] parameter has unknown value(s) [list_and_quoted,_1]. You must enter one of the following values: [list_or_quoted,_2]',
        [ $names, $valids ]
    );
}

=head2 _build_results(VARIABLES, ALLOWED, WANT)

=head3 ARGUMENTS

=over

=item VARIABLES - hashref

Superset of variable name/value pairs.

=item ALLOWED - hashref

With the keys as the internal names and the values as the external names.

=item WANT - array

List of public variable names you want. If not provided, all the allowed variables are returned.

=back

=head3 RETURNS

=over

=item Hashref

With the key/value pairs of the requested variables.

=back

=cut

sub _build_results {
    my ( $variables, $all, @wanted ) = @_;
    my %reverse = reverse %$all;
    my @invalid = grep { !$reverse{$_} } @wanted;
    if (@invalid) {
        _throw_invalid_param( \@invalid, [ keys %reverse ] );
    }

    unless (@wanted) { @wanted = keys %reverse }

    my %returns;
    foreach my $new_key (@wanted) {
        my $internal_key = $reverse{$new_key};
        $returns{$new_key} = $variables->{$internal_key};
    }
    return \%returns;
}

=head2 _transform_results(VARIABLES, TRANSFORMS, BLACKLIST, WANT)

=head3 ARGUMENTS

=over

=item VARIABLES - hashref

Superset of variable name/value pairs.

=item TRANSFORM - hashref

With the keys as the internal names and the values as the external names.

=item BLACKLIST - arrayref

List of variable names you want do not want to make available

=item WANT - array

List of public variable names you want. If not provided, all the allowed variables are returned.

=back

=head3 RETURNS

=over

=item Hashref

With the key/value pairs of the requested variables.

=back

=cut

sub _transform_results {
    my ( $variables, $transforms, $blacklist, @wanted ) = @_;

    # do transforms
    foreach my $key ( keys %{$transforms} ) {
        if ( exists $variables->{$key} ) {
            $variables->{ $transforms->{$key} } = $variables->{$key};
            delete $variables->{$key};
        }
    }

    # delete the blocked key => values
    foreach my $block ( @{$blacklist} ) {
        delete $variables->{$block};
    }

    foreach my $key ( keys %{$variables} ) {

        # lower case all keys
        my $lower_key = lc $key;
        if ( $lower_key ne $key ) {
            $variables->{$lower_key} = $variables->{$key};
            delete $variables->{$key};
        }

        # build feature-*, mxcheck-* data_structures
        if ( $lower_key =~ /^(feature|mxcheck)-(.+)/ ) {
            $variables->{$1}{$2} = ( $1 eq 'mxcheck' && !$variables->{$lower_key} ) ? 'local' : $variables->{$lower_key};
            delete $variables->{$lower_key};
        }
    }
    $variables->{package_extensions} = [ split( ' ', $variables->{package_extensions} ) ]
      if exists $variables->{package_extensions};

    my @invalid = grep { !exists $variables->{$_} } @wanted;
    if (@invalid) {
        _throw_invalid_param( \@invalid, [ keys %{$variables} ] );
    }

    if (@wanted) {
        return { map { $_ => $variables->{$_} } @wanted };
    }
    return $variables;
}

1;
