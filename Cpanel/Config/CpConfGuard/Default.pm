package Cpanel::Config::CpConfGuard::Default;

# cpanel - Cpanel/Config/CpConfGuard/Default.pm    Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics
use Cpanel::Config::Constants          ();
use Cpanel::ConfigFiles                ();
use Cpanel::SSL::DefaultKey::Constants ();                # PPI NO PARSE - mis-parse
use Cpanel::OS                         ();

# These defaults should never be altered in a running process. All static and dynamic keys
# must be added to this list. Ones that are dynamic will not use the value here, but instead
# will call the correct compute_* method to generated the value.
sub default_statics {
    return {
        'RS'                                                  => 'jupiter',
        'VFILTERDIR'                                          => '/etc/vfilters',
        'access_log'                                          => '/usr/local/cpanel/logs/access_log',
        'account_login_access'                                => 'owner_root',
        'selfsigned_generation_for_bestavailable_ssl_install' => '1',
        'allow_deprecated_accesshash'                         => '0',

        'allow_login_autocomplete'                               => '1',
        'allow_server_info_status_from'                          => '',
        'allowcpsslinstall'                                      => '1',
        'allowparkhostnamedomainsubdomains'                      => '0',
        'allowparkonothers'                                      => '0',
        'allowwhmparkonothers'                                   => '0',
        'allowremotedomains'                                     => '0',
        'allowresellershostnamedomainsubdomains'                 => '0',
        'allowunregistereddomains'                               => '0',
        'alwaysredirecttossl'                                    => '1',
        'apache_port'                                            => '0.0.0.0:80',
        'apache_ssl_port'                                        => '0.0.0.0:443',
        'api_shell'                                              => '0',
        'autocreateaentries'                                     => '1',
        'autodiscover_host'                                      => 'cpanelemaildiscovery.cpanel.net',
        'autodiscover_mail_service'                              => 'imap',
        'autodiscover_proxy_subdomains'                          => '1',
        'autoupdate_certificate_on_hostname_mismatch'            => '1',
        'awstatsbrowserupdate'                                   => '0',
        'awstatsreversedns'                                      => '0',
        'bind_deferred_restart_time'                             => '2',
        'httpd_deferred_restart_time'                            => 0,
        'blockcommondomains'                                     => '1',
        'bwcycle'                                                => '2',
        'cgihidepass'                                            => '0',
        'check_zone_owner'                                       => '1',
        'check_zone_syntax'                                      => '1',
        'chkservd_check_interval'                                => '300',
        'chkservd_hang_allowed_intervals'                        => '2',
        'chkservd_plaintext_notify'                              => '0',
        'cluster_autodisable_threshold'                          => '10',
        'cluster_failure_notifications'                          => '1',
        'conserve_memory'                                        => '0',                                                              # dynamic
        'cookieipvalidation'                                     => 'strict',
        'coredump'                                               => '0',
        'cpaddons_adminemail'                                    => '',
        'cpaddons_autoupdate'                                    => '1',
        'cpaddons_max_moderation_req_all_mod'                    => '99',
        'cpaddons_max_moderation_req_per_mod'                    => '99',
        'cpaddons_moderation_request'                            => '0',
        'cpaddons_no_3rd_party'                                  => '0',
        'cpaddons_no_modified_cpanel'                            => '1',
        'cpaddons_notify_owner'                                  => '1',
        'cpaddons_notify_root'                                   => '1',
        'cpaddons_notify_users'                                  => 'Allow users to choose',
        'cpanel_locale'                                          => '',
        'cpdavd_caldav_upload_limit'                             => '10',
        'cpredirect'                                             => 'Origin Domain Name',
        'cpredirectssl'                                          => 'SSL Certificate Name',
        'cpsrvd-domainlookup'                                    => '0',
        'create_account_dkim'                                    => '1',
        'create_account_spf'                                     => '1',
        'csp'                                                    => '0',
        'cycle_hours'                                            => '24',
        'database_prefix'                                        => '1',                                                              # critical
        'debughooks'                                             => '0',
        'debugui'                                                => '0',
        'default_archive-logs'                                   => '1',
        'default_login_theme'                                    => 'cpanel',
        'default_pkg_bwlimit'                                    => '1048576',
        'default_pkg_max_emailacct_quota'                        => '1024',
        'default_pkg_quota'                                      => '10240',
        'default_remove-old-archived-logs'                       => '1',
        'defaultmailaction'                                      => 'localuser',
        'copy_default_error_documents'                           => '0',
        'disable_cphttpd'                                        => '0',
        'disable-php-as-reseller-security'                       => '0',
        'disablequotacache'                                      => '0',
        'display_cpanel_doclinks'                                => '0',
        'display_cpanel_promotions'                              => '1',
        'display_upgrade_opportunities'                          => '0',
        'disk_usage_include_mailman'                             => '1',
        'disk_usage_include_sqldbs'                              => '1',
        'dns_recursive_query_pool_size'                          => '10',
        'dnsadmin_log'                                           => '0',
        'dnsadmin_verbose_sync'                                  => '0',
        'dnsadminapp'                                            => undef,
        'dnslookuponconnect'                                     => '0',
        'docroot'                                                => '/usr/local/cpanel/base',
        'domainowner_mail_pass'                                  => '0',                                                              # dynamic
        'dormant_services'                                       => join( ',', @Cpanel::Config::Constants::DORMANT_SERVICES_LIST ),
        'dumplogs'                                               => '1',
        'email_account_quota_default_selected'                   => 'userdefined',
        'email_account_quota_userdefined_default_value'          => '1024',
        'email_send_limits_count_mailman'                        => '0',
        'email_send_limits_defer_cutoff'                         => '125',
        'email_send_limits_min_defer_fail_to_trigger_protection' => 5,
        'email_send_limits_max_defer_fail_percentage'            => undef,
        'email_outbound_spam_detect_enable'                      => '1',
        'email_outbound_spam_detect_action'                      => 'noaction',
        'email_outbound_spam_detect_threshold'                   => 500,
        'emailarchive'                                           => '0',
        'emailpasswords'                                         => '0',
        'emailsperdaynotify'                                     => undef,
        'emailusers_diskusage_critical_contact_admin'            => '1',
        'emailusers_diskusage_critical_percent'                  => '90',
        'emailusers_diskusage_full_contact_admin'                => '1',
        'emailusers_diskusage_full_percent'                      => '98',
        'emailusers_diskusage_warn_contact_admin'                => '0',
        'emailusers_diskusage_warn_percent'                      => '80',
        'emailusers_mailbox_critical_percent'                    => '90',
        'emailusers_mailbox_full_percent'                        => '98',
        'emailusers_mailbox_warn_percent'                        => '80',
        'emailusersbandwidthexceed'                              => '1',
        'emailusersbandwidthexceed70'                            => '0',
        'emailusersbandwidthexceed75'                            => '0',
        'emailusersbandwidthexceed80'                            => '1',
        'emailusersbandwidthexceed85'                            => '0',
        'emailusersbandwidthexceed90'                            => '0',
        'emailusersbandwidthexceed95'                            => '0',
        'emailusersbandwidthexceed97'                            => '0',
        'emailusersbandwidthexceed98'                            => '0',
        'emailusersbandwidthexceed99'                            => '0',
        'empty_trash_days'                                       => 'disabled',
        'enable_piped_logs'                                      => '1',
        'enablefileprotect'                                      => '1',
        'enablecompileroptimizations'                            => '0',
        'enforce_user_account_limits'                            => '0',
        'engine'                                                 => 'cpanel',
        'enginepl'                                               => 'cpanel.pl',
        'engineroot'                                             => '/usr/local/cpanel',
        'exim-retrytime'                                         => '15',
        'exim_retention_days'                                    => '10',
        'eximmailtrap'                                           => '1',                                                              # dynamic
        'extracpus'                                              => '0',
        'file_upload_max_bytes'                                  => undef,
        'file_upload_must_leave_bytes'                           => '5',
        'file_usage'                                             => '0',
        'force_short_prefix'                                     => '0',
        'ftpquotacheck_expire_time'                              => '30',
        'ftpserver'                                              => 'disabled',                                                       # dynamic, critical
        'gzip_compression_level'                                 => '6',
        'gzip_pigz_block_size'                                   => '4096',
        'gzip_pigz_processes'                                    => '1',                                                              # dynamic
        'htaccess_check_recurse'                                 => '2',
        'invite_sub'                                             => '1',
        'ionice_bandwidth_processing'                            => '6',
        'ionice_cpbackup'                                        => '6',
        'ionice_dovecot_maintenance'                             => '7',
        'ionice_email_archive_maintenance'                       => '7',
        'ionice_ftpquotacheck'                                   => '6',
        'ionice_log_processing'                                  => '7',
        'ionice_quotacheck'                                      => '6',
        'ionice_userbackup'                                      => '7',
        'ionice_userproc'                                        => '6',
        'ipv6_control'                                           => '0',
        'ipv6_listen'                                            => '0',
        'jailapache'                                             => '0',
        'jaildefaultshell'                                       => '0',
        'jailmountbinsuid'                                       => '0',
        'jailmountusrbinsuid'                                    => '0',
        'jailprocmode'                                           => 'mount_proc_jailed_fallback_full',
        'keepftplogs'                                            => '0',
        'keeplogs'                                               => '0',
        'keepstatslog'                                           => '0',
        'loadthreshold'                                          => undef,
        'local_nameserver_type'                                  => 'powerdns',                                                       # dynamic, critical
        'logchmod'                                               => '0640',
        'log_successful_logins'                                  => 0,
        'logout_redirect_url'                                    => '',
        'mailbox_storage_format'                                 => 'maildir',                                                        #keep in sync with cpuser
        'mailserver'                                             => 'dovecot',                                                        # dynamic, critical
        'maxcpsrvdconnections'                                   => '200',
        'maxemailsperhour'                                       => undef,

        # dynamic
        # Also please keep in sync with Cpanel::Maxmem.
        'maxmem' => '4096',

        'minpwstrength'                                     => '65',
        'min_time_between_apache_graceful_restarts'         => '10',
        'modsec_keep_hits'                                  => '7',
        'mycnf_auto_adjust_openfiles_limit'                 => '1',
        'mycnf_auto_adjust_maxallowedpacket'                => '1',
        'mycnf_auto_adjust_innodb_buffer_pool_size'         => '0',
        'mysql-host'                                        => 'localhost',                                        # dynamic, critical
        'mysql-version'                                     => undef,                                              # dynamic, critical
        'maintenance_rpm_version_check'                     => '1',
        'maintenance_rpm_version_digest_check'              => '1',
        'nobodyspam'                                        => '1',
        'notify_expiring_certificates'                      => '1',
        'nocpbackuplogs'                                    => '0',
        'nosendlangupdates'                                 => '0',
        'numacctlist'                                       => '30',
        'overwritecustomproxysubdomains'                    => '0',
        'overwritecustomsrvrecords'                         => '0',
        'permit_appconfig_entries_without_acls'             => '0',
        'permit_appconfig_entries_without_features'         => '0',
        'permit_unregistered_apps_as_reseller'              => '0',
        'permit_unregistered_apps_as_root'                  => '0',
        'php_max_execution_time'                            => '90',
        'php_memory_limit'                                  => '128',
        'php_post_max_size'                                 => '55',
        'php_upload_max_filesize'                           => '50',
        'phploader'                                         => '',
        'pma_disableis'                                     => '0',
        'phpopenbasedirhome'                                => '0',
        'popbeforesmtpsenders'                              => '0',
        'popbeforesmtp'                                     => '0',
        'product'                                           => 'cPanel',
        'proxysubdomains'                                   => '1',                                                # dynamic, critical
        'proxysubdomainsoverride'                           => '1',
        'publichtmlsubsonly'                                => '1',
        'query_apache_for_nobody_senders'                   => '1',
        'referrerblanksafety'                               => '0',
        'referrersafety'                                    => '0',
        'remotewhmtimeout'                                  => '35',
        'repquota_timeout'                                  => '60',
        'requiressl'                                        => '1',
        'resetpass'                                         => '1',
        'resetpass_sub'                                     => '1',
        'root'                                              => '/usr/local/cpanel',
        'rotatelogs_size_threshhold_in_megabytes'           => '300',
        'roundcube_db'                                      => 'sqlite',
        'rpmup_allow_kernel'                                => '0',
        'send_error_reports'                                => '0',
        'server_locale'                                     => 'en',
        'share_docroot_default'                             => '1',
        'showwhmbwusageinmegs'                              => '0',
        'show_reboot_banner'                                => '1',
        'signature_validation'                              => 'Release Keyring Only',                             # dynamic
        'skip_chkservd_recovery_notify'                     => '0',
        'skipanalog'                                        => '0',
        'skiprecentauthedmailiptracker'                     => '0',
        'skipapacheclientsoptimizer'                        => '0',
        'skipawstats'                                       => '0',
        'skipboxcheck'                                      => '1',
        'skipboxtrapper'                                    => '0',
        'skipbwlimitcheck'                                  => '0',
        'skipchkservd'                                      => '0',
        'skipcpbandwd'                                      => '0',
        'skipdiskcheck'                                     => '0',
        'skipoomcheck'                                      => '0',
        'skipdiskusage'                                     => '0',
        'skipeximstats'                                     => '0',
        'skipfirewall'                                      => '0',
        'skip_rules_added_by_configure_firewall_for_cpanel' => '0',
        'skiphttpauth'                                      => '1',
        'skipjailmanager'                                   => '0',
        'skipmailauthoptimizer'                             => '0',
        'skipmailman'                                       => '0',
        'skipmodseclog'                                     => '0',
        'skipnotifyacctbackupfailure'                       => '0',
        'skipparentcheck'                                   => '0',
        'skiproundcube'                                     => '0',
        'skipspamassassin'                                  => '0',
        'skipspambox'                                       => '0',
        'skiptailwatchd'                                    => '0',
        'skipwebalizer'                                     => '0',
        'smtpmailgidonly'                                   => '1',
        'ssh_host_key_checking'                             => '0',
        'stats_log'                                         => '/usr/local/cpanel/logs/stats_log',
        'statsloglevel'                                     => '1',
        'statthreshhold'                                    => '256',
        'system_diskusage_critical_percent'                 => '92.55',
        'system_diskusage_warn_percent'                     => '82.55',
        'tcp_check_failure_threshold'                       => '3',
        'ssl_default_key_type'                              => (Cpanel::SSL::DefaultKey::Constants::OPTIONS)[0],
        'transfers_timeout'                                 => '1800',
        'tweak_unset_vars'                                  => '',
        'update_log_analysis_retention_length'              => '90',
        'upcp_log_retention_days'                           => '45',
        'use_apache_md5_for_htaccess'                       => '1',
        'use_information_schema'                            => '1',
        'useauthnameservers'                                => '0',
        'usemailformailmanurl'                              => '0',
        'usemysqloldpass'                                   => '0',
        'userdirprotect'                                    => '1',
        'verify_3rdparty_cpaddons'                          => '0',
        'version'                                           => '3.4',
        'xframecpsrvd'                                      => '1',
        'enable_api_log'                                    => '0',
    };
}

sub default_dead_variables {
    return [
        qw /
          SecurityPolicy::NoRootLogin SecurityPolicy::PasswdAge SecurityPolicy::PasswdAge::maxage SecurityPolicy::PasswdStrength
          cppop cycle disablerootlogin allowperlupdates deny_quicksupport_password email_account_quota_display enable_cpansqlite
          maildir force_binary_rrdtool php_register_globals popchecktimes popfloodcheck skipmelange send_update_log_for_analysis
          interchangever ionice_optimizefs userstatsoverride skiplogaholic hordeadmins gzip_use_pigz skipantirelayd python cpsrvd-gzip
          urchinsetpath stunnel nativessl dnsadmin_as_daemon port minpwstrength_bandmin disableipnscheck security_advice_changes_notifications
          skipwhoisns horde_cache_empty_days skiphorde
          skipformmail discardformmailbccsubject anon_data_optout ftppasslogs allow_weak_checksums skipsqmail send_server_configuration send_server_usage
          global_dcv_rewrite_exclude ignoredepreciated
          /
    ];
}

# NOTE: if your variable is in etc/cpanel.config then it will not be computed on a fresh install
# because updatenow.static will merge etc/cpanel.config to /var/cpanel/cpanel.config and existing keys are not
# re-computed.
sub dynamic_variable_methods {
    return {
        'autodiscover_proxy_subdomains' => \&compute_autodiscover_proxy_subdomains,
        'conserve_memory'               => \&compute_conserve_memory,
        'domainowner_mail_pass'         => \&compute_domainowner_mail_pass,
        'dormant_services'              => \&compute_dormant_services,
        'eximmailtrap'                  => \&compute_eximmailtrap,
        'ftpserver'                     => \&compute_ftpserver,
        'gzip_pigz_processes'           => \&compute_system_processes,
        'mailserver'                    => \&compute_mailserver,
        'maxmem'                        => \&compute_maxmem,
        'enablefileprotect'             => \&compute_enablefileprotect,
        'mysql-host'                    => \&compute_mysql_host,
        'mysql-version'                 => \&compute_mysql_version,
        'proxysubdomains'               => \&compute_proxysubdomains,
        'signature_validation'          => \&compute_signature_validation,
    };
}

sub critical_values {

    return [
        qw/
          mysql-version
          mysql-host
          mailserver
          ftpserver
          server_locale
          autodiscover_proxy_subdomains
          proxysubdomains
          database_prefix
          /
    ];
}

sub new {
    my ( $class, %OPTS ) = @_;

    # Load in defaults passed into the constructor.
    my %data;
    my @class_variables = qw/dynamic_variable_method defaults default_file_contents keys dead_variables current_config current_changes/;
    @data{@class_variables} = @OPTS{@class_variables};

    # Default some values if not passed in.
    $data{'dynamic_variable_method'} ||= dynamic_variable_methods();
    $data{'default_file_contents'}   ||= default_statics();
    $data{'dead_variables'}          ||= default_dead_variables();
    $data{'is_root'}                 ||= ( $> == 0 ) ? 1 : 0;
    $data{'current_config'}          ||= {};

    my $self = bless \%data, $class;

    $self->init;

    return $self;
}

sub init {
    my ($self) = @_;
    _verify_called_as_object_method($self);

    return if ( $self->{'defaults'} );    # Don't re-load as long as defaults is populated.

    my $defaults = $self->{'default_file_contents'};

    # Store the total list of keys found in cpanel.config
    $self->{'keys'} = [ keys %$defaults ];

    # Populate defaults with ONLY the static methods.

    $self->{'defaults'} = {};
    foreach my $key ( sort keys %$defaults ) {
        next if $self->{'dynamic_variable_method'}->{$key};    # Not a static variable.
        $self->{'defaults'}->{$key} = $defaults->{$key};
    }

    # force initial_install to be cached because various code paths set CPANEL_BASE_INSTALL=0 to workaround other issues
    # but we'd like our compute methods to understand the context when this object was constructed.
    $self->initial_install();

    return 1;
}

sub initial_install {
    my ($self) = @_;
    _verify_called_as_object_method($self);

    if ( !defined $self->{'initial_install'} ) {
        $self->{'initial_install'} = $ENV{'CPANEL_BASE_INSTALL'} || 0;
    }
    return $self->{'initial_install'};
}

sub get_all_defaults {
    my ($self) = @_;
    _verify_called_as_object_method($self);

    # Force defaults to be calculated.
    foreach my $key ( keys %{ $self->{'dynamic_variable_method'} } ) {
        $self->get_default_for($key);
    }
    return $self->{'defaults'};
}

sub is_dynamic {
    my ( $self, $key ) = @_;
    _verify_called_as_object_method($self);

    return $self->{'dynamic_variable_method'}->{$key} ? 1 : 0;
}

sub get_keys {
    my ($self) = @_;
    _verify_called_as_object_method($self);

    return @{ $self->{keys} };
}

sub get_dynamic_keys_hash {
    my ($self) = @_;
    _verify_called_as_object_method($self);

    my %keys_hash = map { ( $_ => 1 ) } keys %{ $self->{'dynamic_variable_method'} };
    return \%keys_hash;
}

# _verify_called_as_object_method is skipped here because
# we call this in a tight loop
sub get_static_default_for {
    return $_[0]->{'default_file_contents'}->{ $_[1] };
}

sub get_default_for {
    my ( $self, $key ) = @_;
    _verify_called_as_object_method($self);

    my $defaults = $self->{'defaults'};

    # undef values are allowed for now.
    return $defaults->{$key} if exists $defaults->{$key};
    return $self->get_dynamic_key($key);
}

sub dead_variables {
    my ($self) = @_;
    _verify_called_as_object_method($self);

    return $self->{'dead_variables'} || [];
}

sub get_dynamic_key {
    my ( $self, $key ) = @_;
    _verify_called_as_object_method($self);

    my $code = $self->{'dynamic_variable_method'}->{$key};
    return unless ( $code && ref $code eq 'CODE' );

    return $self->{'defaults'}->{$key} = $code->($self);
}

sub compute_autodiscover_proxy_subdomains {
    my $self = shift;
    _verify_called_as_object_method($self);

    return 0 unless $self->{'is_root'};    # Cannot figure this out reliably when not root.

    # We just go with the default on a fresh install.
    return $self->get_static_default_for('autodiscover_proxy_subdomains') if $self->initial_install;

    require Cpanel::LoadFile;
    return 0 unless -e apache_paths_facade->file_conf();
    my $sr = Cpanel::LoadFile::load_r( apache_paths_facade->file_conf() );
    substr( $$sr, 0, 0, "\n" );
    return $$sr =~ m{\n[ \t]*ServerAlias.*autodiscover\.}s ? 1 : 0;
}

sub compute_conserve_memory {
    my $self = shift;
    _verify_called_as_object_method($self);

    # We just go with the default on a fresh install.
    return $self->get_static_default_for('autodiscover_conserve_memory') if $self->initial_install;

    return _check_file('/var/cpanel/conserve_memory');
}

sub compute_domainowner_mail_pass {
    my $self = shift;
    _verify_called_as_object_method($self);

    # We just go with the default on a fresh install.
    return $self->get_static_default_for('domainowner_mail_pass') if $self->initial_install;

    return _check_file('/var/cpanel/allow_domainowner_mail_pass');
}

sub compute_dormant_services {
    my $self = shift;
    _verify_called_as_object_method($self);

    # We just go with the default on a fresh install.
    return $self->get_static_default_for('dormant_services') if $self->initial_install;

    return '' unless $self->{'is_root'};    # Cannot figure this out reliably when not root.

    return '' unless -d $Cpanel::ConfigFiles::DORMANT_SERVICES_DIR;

    return join( ',', map { -f $Cpanel::ConfigFiles::DORMANT_SERVICES_DIR . "/$_/enabled" ? $_ : () } @Cpanel::Config::Constants::DORMANT_SERVICES_LIST );
}

sub compute_enablefileprotect {
    my $self = shift;
    _verify_called_as_object_method($self);

    # We just go with the default on a fresh install.
    return $self->get_static_default_for('enablefileprotect') if $self->initial_install;

    return _check_file('/var/cpanel/fileprotect');
}

sub compute_eximmailtrap {
    my $self = shift;
    _verify_called_as_object_method($self);

    # We just go with the default on a fresh install.
    return $self->get_static_default_for('eximmailtrap') if $self->initial_install;

    return _check_file('/etc/eximmailtrap');
}

sub compute_ftpserver {
    my $self = shift;
    _verify_called_as_object_method($self);

    return 'disabled' unless $self->{'is_root'};    # Cannot figure this out reliably when not root.

    # We just go with the default on a fresh install.
    return $self->get_static_default_for('ftpserver') if $self->initial_install;

    require Cpanel::Services::Enabled;
    return 'disabled' unless Cpanel::Services::Enabled::is_enabled('ftp');

    my @servers = (qw/pure-ftpd proftpd/);
    require Cpanel::Pkgr;
    my $ftps = Cpanel::Pkgr::query(@servers);

    if ($ftps) {
        for my $is_cprpm ( 1, 0 ) {

            # two passes: during the first one try to check a cPanel rpm
            foreach my $search (@servers) {
                return $search
                  if $ftps->{$search}
                  && ( !$is_cprpm || $ftps->{$search} =~ m/\.cp\d+$/ );
            }
        }
    }

    return 'disabled';
}

sub compute_system_processes {
    my $self = shift;
    _verify_called_as_object_method($self);

    return 1 unless $self->{'is_root'};    # Cannot figure this out reliably when not root.

    require Cpanel::Cpu;
    return Cpanel::Cpu::get_physical_cpu_count();
}

sub compute_mailserver {
    my $self = shift;
    _verify_called_as_object_method($self);

    require Cpanel::Services::Enabled;
    return 'disabled' unless Cpanel::Services::Enabled::is_enabled('mail');

    # Dovecot is required for exim so if the mailserver is enabled, we should assume dovecot.
    return 'dovecot';
}

sub compute_maxmem {
    require Cpanel::Maxmem;
    return Cpanel::Maxmem::default();
}

sub compute_mysql_host {
    my $self = shift;
    _verify_called_as_object_method($self);

    # We just go with the default on a fresh install.
    return $self->get_static_default_for('mysql-host') if $self->initial_install;

    # Cannot figure this out reliably when not root.
    return $self->get_static_default_for('mysql-host') unless $self->{'is_root'};

    require Cpanel::MysqlUtils::MyCnf::Basic;
    return Cpanel::MysqlUtils::MyCnf::Basic::getmydbhost('root') || $self->get_static_default_for('mysql-host');
}

sub compute_mysql_version {
    my $self = shift;
    _verify_called_as_object_method($self);

    # TODO: If we fix cached-command to support non-root, then this wouldn't be necessary.

    my $default_version = Cpanel::OS::mysql_default_version();

    return $default_version unless $self->{'is_root'};

    # We just go with the default on a fresh install.
    return $default_version if $self->initial_install;

    eval q/require Cpanel::MysqlUtils::Version; 1/ or return;    ## no critic qw(BuiltinFunctions::ProhibitStringyEval) - hide from updatenow.static generation

    local $@;
    my $version = eval { Cpanel::MysqlUtils::Version::mysqlversion() };
    $version ||= Cpanel::MysqlUtils::Version::get_short_mysql_version_from_data_files();

    no warnings 'once';
    $version ||= $Cpanel::MysqlUtils::Version::DEFAULT_MYSQL_RELEASE_TO_ASSUME_IS_INSTALLED;

    return $version;
}

sub compute_proxysubdomains {
    my $self = shift;
    _verify_called_as_object_method($self);

    # We just go with the default on a fresh install.
    return $self->get_static_default_for('proxysubdomains') if $self->initial_install;

    return 0 unless -r apache_paths_facade->file_conf();

    require Cpanel::SafeRun::Simple;
    return 1 if Cpanel::SafeRun::Simple::saferun( 'grep', '-l', '^# CPANEL/.*PROXY SUBDOMAINS', apache_paths_facade->file_conf() ) && $? == 0;
    return 0;
}

sub compute_signature_validation {
    my $self = shift;
    _verify_called_as_object_method($self);

    require Cpanel::Crypt::GPG::Settings;
    return Cpanel::Crypt::GPG::Settings::validation_setting_for_configured_mirror(),;
}

# mainly for testing purpose
sub _check_file {
    my $f = shift or return 0;
    return -e $f ? 1 : 0;
}

sub _verify_called_as_object_method {
    my $call = shift;
    ref($call) eq __PACKAGE__ or die '' . ( caller(0) )[3] . " was not called as an object method line " . ( caller(0) )[2] . "\n";
    return;
}

1;
