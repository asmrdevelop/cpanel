package Cpanel::ConfigFiles;

# cpanel - Cpanel/ConfigFiles.pm                     Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# Do not use() any modules here: the intent of this module is to be a
#    lightweight way to know where all the config files are.
#    If a module is needed it must be require()d at runtime only when
#     needed (we can't use Cpanel::LoadModule here as it adds 450 to RSS).

our $VERSION = '1.4';

# These should not be changed, only exposed for the purpose of testing.
our $cpanel_users       = '/var/cpanel/users';
our $cpanel_users_cache = '/var/cpanel/users.cache';

# backup related config files. If $backup_config_touchfile exists, metadata and file restoration is disabled
our $backup_config_touchfile     = '/var/cpanel/config/backups/metadata_disabled';
our $backup_config_touchfile_dir = '/var/cpanel/config/backups/';
our $backup_config               = '/var/cpanel/backups/config';

#TODO: Move these to Cpanel/Config/CpConfGuard.pm
our $cpanel_config_file          = '/var/cpanel/cpanel.config';
our $cpanel_config_cache_file    = '/var/cpanel/cpanel.config.cache';
our $cpanel_config_defaults_file = '/usr/local/cpanel/etc/cpanel.config';
our $features_cache_dir          = "/var/cpanel/features.cache";

our $BASE_INSTALL_IN_PROGRESS_FILE = '/root/installer.lock';

our $CPSRVD_CHECK_CPLISC_FILE = q{/var/cpanel/cpsrvd_check_license};

our $ROOT_CPANEL_HOMEDIR = '/var/cpanel/userhomes/cpanel';

our $RESELLERS_FILE             = '/var/cpanel/resellers';
our $RESELLERS_NAMESERVERS_FILE = '/var/cpanel/resellers-nameservers';
our $ACCOUNTING_LOG_FILE        = '/var/cpanel/accounting.log';
our $FEATURES_DIR               = '/var/cpanel/features';
our $BANDWIDTH_LIMIT_DIR        = '/var/cpanel/bwlimited';
our $CUSTOM_PERL_MODULES_DIR    = '/var/cpanel/perl';
our $PACKAGES_DIR;    #defined below

our $DEDICATED_IPS_FILE       = '/etc/domainips';
our $DELEGATED_IPS_DIR        = '/var/cpanel/dips';
our $MAIN_IPS_DIR             = '/var/cpanel/mainips';
our $RESERVED_IPS_FILE        = '/etc/reservedips';
our $RESERVED_IP_REASONS_FILE = '/etc/reservedipreasons';
our $IP_ADDRESS_POOL_FILE     = '/etc/ipaddrpool';
our $ACL_LISTS_DIR            = '/var/cpanel/acllists';

our $OUTGOING_MAIL_SUSPENDED_USERS_FILE    = '/etc/outgoing_mail_suspended_users';
our $OUTGOING_MAIL_HOLD_USERS_FILE         = '/etc/outgoing_mail_hold_users';
our $TRUEUSEROWNERS_FILE                   = '/etc/trueuserowners';
our $TRUEUSERDOMAINS_FILE                  = '/etc/trueuserdomains';
our $USERDOMAINS_FILE                      = '/etc/userdomains';
our $DBOWNERS_FILE                         = '/etc/dbowners';
our $DOMAINUSERS_FILE                      = '/etc/domainusers';
our $LOCALDOMAINS_FILE                     = '/etc/localdomains';
our $REMOTEDOMAINS_FILE                    = '/etc/remotedomains';
our $SECONDARYMX_FILE                      = '/etc/secondarymx';
our $MANUALMX_FILE                         = '/etc/manualmx';
our $USERBWLIMITS_FILE                     = '/etc/userbwlimits';
our $MAILIPS_FILE                          = '/etc/mailips';
our $MAILHELO_FILE                         = '/etc/mailhelo';
our $NEIGHBOR_NETBLOCKS_FILE               = '/etc/neighbor_netblocks';
our $CPANEL_MAIL_NETBLOCKS_FILE            = '/etc/cpanel_mail_netblocks';
our $GREYLIST_TRUSTED_NETBLOCKS_FILE       = '/etc/greylist_trusted_netblocks';
our $GREYLIST_COMMON_MAIL_PROVIDERS_FILE   = '/etc/greylist_common_mail_providers';
our $RECENT_RECIPIENT_MAIL_SERVER_IPS_FILE = '/etc/recent_recipient_mail_server_ips';
our $DEMOUSERS_FILE                        = '/etc/demousers';

our $APACHE_CONFIG_DIR          = '/var/cpanel/conf/apache';
our $APACHE_PRIMARY_VHOSTS_FILE = '/var/cpanel/conf/apache/primary_virtual_hosts.conf';

our $MYSQL_CNF = '/etc/my.cnf';

our $SERVICEAUTH_DIR      = '/var/cpanel/serviceauth';
our $DORMANT_SERVICES_DIR = '/var/cpanel/dormant_services';

our $DOMAIN_KEYS_ROOT = '/var/cpanel/domain_keys';

our $USER_NOTIFICATIONS_DIR = '/var/cpanel/user_notifications';

our $DATABASES_INFO_DIR = '/var/cpanel/databases';

our $CPANEL_ROOT  = '/usr/local/cpanel';
our $MAILMAN_ROOT = "$CPANEL_ROOT/3rdparty/mailman";

our $FPM_CONFIG_ROOT = "/var/cpanel/php-fpm.d";
our $FPM_ROOT        = "/var/cpanel/php-fpm";

our $MAILMAN_LISTS_DIR = "$MAILMAN_ROOT/lists";

our $MAILMAN_USER = 'mailman';

our $FTP_PASSWD_DIR     = '/etc/proftpd';
our $FTP_SYMLINKS_DIR   = '/etc/pure-ftpd';
our $VALIASES_DIR       = '/etc/valiases';
our $VDOMAINALIASES_DIR = '/etc/vdomainaliases';
our $VFILTERS_DIR       = '/etc/vfilters';

our $JAILSHELL_PATH = '/usr/local/cpanel/bin/jailshell';

our @COMMONDOMAINS_FILES = qw{/usr/local/cpanel/etc/commondomains /var/cpanel/commondomains};

our $BANDWIDTH_DIRECTORY             = '/var/cpanel/bandwidth';
our $BANDWIDTH_CACHE_DIRECTORY       = '/var/cpanel/bandwidth.cache';
our $BANDWIDTH_USAGE_CACHE_DIRECTORY = '/var/cpanel/bwusagecache';

our $TEMPLATE_COMPILE_DIR = '/var/cpanel/template_compiles';

our $DOVECOT_SNI_CONF = '/etc/dovecot/sni.conf';

our $DOVECOT_SSL_CONF = '/etc/dovecot/ssl.conf';
our $DOVECOT_SSL_KEY  = '/etc/dovecot/ssl/dovecot.key';
our $DOVECOT_SSL_CRT  = '/etc/dovecot/ssl/dovecot.crt';

our $GOOGLE_AUTH_TEMPFILE_PREFIX = '/var/cpanel/backups/google_oauth_tempfile_';

our $APACHE_LOGFILE_CLEANUP_QUEUE = '/var/cpanel/apache_logfile_cleanup.json';

our $SKIP_REPO_SETUP_FLAG = '/var/cpanel/skip-repo-setup';

our $ACCOUNT_ENHANCEMENTS_DIR          = '/var/cpanel/account_enhancements';
our $ACCOUNT_ENHANCEMENTS_CONFIG_DIR   = $Cpanel::ConfigFiles::ACCOUNT_ENHANCEMENTS_DIR . '/config';
our $ACCOUNT_ENHANCEMENTS_INSTALL_FILE = $Cpanel::ConfigFiles::ACCOUNT_ENHANCEMENTS_CONFIG_DIR . '/installed.json';

BEGIN {
    $PACKAGES_DIR = '/var/cpanel/packages';
}

#----------------------------------------------------------------------

1;
