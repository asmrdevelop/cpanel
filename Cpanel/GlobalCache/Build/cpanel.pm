package Cpanel::GlobalCache::Build::cpanel;

# cpanel - Cpanel/GlobalCache/Build/cpanel.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

## no critic qw(TestingAndDebugging::RequireUseStrict TestingAndDebugging::RequireUseWarnings)

use Cpanel::DbUtils                      ();
use Cpanel::GlobalCache::Build           ();
use Cpanel::ConfigFiles::Apache::modules ();
use Cpanel::ConfigFiles::Apache          ();
use Cpanel::Config::LoadWwwAcctConf      ();
use Cpanel::Sys::Hostname                ();
use Cpanel::Sys::Uname                   ();
use Cpanel::FindBin                      ();
use Cpanel::Binaries                     ();
use Cpanel::ModSecurity                  ();
use Cpanel::PostgresAdmin::Check         ();
use Cpanel::Services::Enabled            ();
use Cpanel::Version                      ();
use Cpanel::Market::Tiny                 ();
use Cpanel::SSL::Auto::Config::Read      ();
use Cpanel::Config::LoadCpConf           ();
use Cpanel::MysqlUtils::MyCnf::Basic     ();
use Cpanel::DNSSEC::Available            ();
use Cpanel::DAV::Provider                ();
use Cpanel::OS                           ();

our $ENVTYPE_PATH        = '/var/cpanel/envtype';
our $PASSENGER_APPS_PATH = '/etc/cpanel/ea4/passenger.ruby';

sub build {
    my $ethdev;
    my $cpconf_ref      = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    my $apacheconf      = Cpanel::ConfigFiles::Apache->new();
    my $wwwaccthash_ref = Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();
    if ( defined $wwwaccthash_ref->{'ETHDEV'}
        && $wwwaccthash_ref->{'ETHDEV'} ne '' ) {
        $ethdev = $wwwaccthash_ref->{'ETHDEV'};
    }

    my $autossl_conf = Cpanel::SSL::Auto::Config::Read->new();
    my $metadata     = $autossl_conf->get_metadata();

    my $autossl_clobber_externally_signed             = $metadata->{"clobber_externally_signed"} || 0;
    my $notify_autossl_expiry                         = $metadata->{"notify_autossl_expiry"};
    my $notify_autossl_expiry_coverage                = $metadata->{"notify_autossl_expiry_coverage"};
    my $notify_autossl_renewal_coverage               = $metadata->{"notify_autossl_renewal_coverage"};
    my $notify_autossl_renewal_coverage_reduced       = $metadata->{"notify_autossl_renewal_coverage_reduced"};
    my $notify_autossl_renewal_uncovered_domains      = $metadata->{"notify_autossl_renewal_uncovered_domains"};
    my $notify_autossl_renewal                        = $metadata->{"notify_autossl_renewal"};
    my $notify_autossl_expiry_user                    = $metadata->{"notify_autossl_expiry_user"};
    my $notify_autossl_expiry_coverage_user           = $metadata->{"notify_autossl_expiry_coverage_user"};
    my $notify_autossl_renewal_coverage_user          = $metadata->{"notify_autossl_renewal_coverage_user"};
    my $notify_autossl_renewal_coverage_reduced_user  = $metadata->{"notify_autossl_renewal_coverage_reduced_user"};
    my $notify_autossl_renewal_uncovered_domains_user = $metadata->{"notify_autossl_renewal_uncovered_domains_user"};
    my $notify_autossl_renewal_user                   = $metadata->{"notify_autossl_renewal_user"};
    my $autossl_provider                              = $autossl_conf->get_provider();
    my $display_cpanel_doclinks                       = $cpconf_ref->{'display_cpanel_doclinks'}   ? 1 : 0;
    my $display_cpanel_promotions                     = $cpconf_ref->{'display_cpanel_promotions'} ? 1 : 0;

    my $options_support  = Cpanel::ConfigFiles::Apache::modules::_get_options_support();
    my $compiled_support = Cpanel::ConfigFiles::Apache::modules::_get_compiled_support();
    my $keyref           = [
        ( $ethdev ? ( { 'type' => 'command', 'key' => [ '/sbin/ip', '-4', 'addr', 'show', $ethdev ], 'keeplines' => 3 } ) : () ),
        { 'type' => 'data',    'key' => 'Cpanel::ConfigFiles::Apache::modules::_get_options_support',  'value' => $options_support },
        { 'type' => 'data',    'key' => 'Cpanel::ConfigFiles::Apache::modules::_get_compiled_support', 'value' => $compiled_support },
        { 'type' => 'data',    'key' => 'display_cpanel_doclinks',                                     'value' => $display_cpanel_doclinks },
        { 'type' => 'data',    'key' => 'display_cpanel_promotions',                                   'value' => $display_cpanel_promotions },
        { 'type' => 'command', 'key' => [ $apacheconf->bin_httpd(), '-v' ] },
        { 'type' => 'command', 'key' => [ Cpanel::Binaries::path('perl'), '-v' ], 'keeplines' => 3 },
        { 'type' => 'file',    'key' => $ENVTYPE_PATH },
        { 'type' => 'data',    'key' => 'hostname',                                      'value' => Cpanel::Sys::Hostname::gethostname() },
        { 'type' => 'data',    'key' => 'autossl_clobber_externally_signed',             'value' => $autossl_clobber_externally_signed },
        { 'type' => 'data',    'key' => 'notify_autossl_expiry',                         'value' => $notify_autossl_expiry },
        { 'type' => 'data',    'key' => 'notify_autossl_expiry_coverage',                'value' => $notify_autossl_expiry_coverage },
        { 'type' => 'data',    'key' => 'notify_autossl_renewal_coverage_reduced',       'value' => $notify_autossl_renewal_coverage_reduced },
        { 'type' => 'data',    'key' => 'notify_autossl_renewal_uncovered_domains',      'value' => $notify_autossl_renewal_uncovered_domains },
        { 'type' => 'data',    'key' => 'notify_autossl_renewal_coverage',               'value' => $notify_autossl_renewal_coverage },
        { 'type' => 'data',    'key' => 'notify_autossl_renewal',                        'value' => $notify_autossl_renewal },
        { 'type' => 'data',    'key' => 'notify_autossl_expiry_user',                    'value' => $notify_autossl_expiry_user },
        { 'type' => 'data',    'key' => 'notify_autossl_expiry_coverage_user',           'value' => $notify_autossl_expiry_coverage_user },
        { 'type' => 'data',    'key' => 'notify_autossl_renewal_coverage_reduced_user',  'value' => $notify_autossl_renewal_coverage_reduced_user },
        { 'type' => 'data',    'key' => 'notify_autossl_renewal_uncovered_domains_user', 'value' => $notify_autossl_renewal_uncovered_domains_user },
        { 'type' => 'data',    'key' => 'notify_autossl_renewal_coverage_user',          'value' => $notify_autossl_renewal_coverage_user },
        { 'type' => 'data',    'key' => 'notify_autossl_renewal_user',                   'value' => $notify_autossl_renewal_user },
        { 'type' => 'data',    'key' => 'autossl_current_provider_name',                 'value' => $autossl_provider },
        { 'type' => 'data',    'key' => 'version_display',                               'value' => Cpanel::Version::get_version_display() },
        { 'type' => 'data',    'key' => 'version_parent',                                'value' => Cpanel::Version::get_version_parent() },
        { 'type' => 'data',    'key' => 'release',                                       'value' => ( Cpanel::Sys::Uname::get_uname_cached() )[2] },
        { 'type' => 'data',    'key' => 'has_cloudlinux',                                'value' => scalar Cpanel::OS::is_cloudlinux() },
        { 'type' => 'data',    'key' => 'has_modsecurity_installed',                     'value' => scalar Cpanel::ModSecurity::has_modsecurity_installed() },
        { 'type' => 'data',    'key' => 'market_has_enabled_providers',                  'value' => Cpanel::Market::Tiny::get_enabled_providers_count() ? 1 : 0 },
        { 'type' => 'data',    'key' => 'has_postgres',                                  'value' => Cpanel::PostgresAdmin::Check::is_configured()->{'status'} },
        { 'type' => 'data',    'key' => 'has_remote_mysql',                              'value' => Cpanel::MysqlUtils::MyCnf::Basic::is_remote_mysql() },
        { 'type' => 'data',    'key' => 'hascpdavd',                                     'value' => Cpanel::Services::Enabled::is_enabled('cpdavd') },
        { 'type' => 'data',    'key' => 'hassolr',                                       'value' => Cpanel::Services::Enabled::is_enabled('cpanel-dovecot-solr') },
        { 'type' => 'data',    'key' => 'hasmoddeflate',                                 'value' => Cpanel::ConfigFiles::Apache::modules::is_supported('mod_deflate')              ? 1 : 0 },
        { 'type' => 'data',    'key' => 'hasmodproxy',                                   'value' => Cpanel::ConfigFiles::Apache::modules::is_supported('mod_proxy')                ? 1 : 0 },
        { 'type' => 'data',    'key' => 'hasgem',                                        'value' => Cpanel::FindBin::findbin('gem')                                                ? 1 : 0 },
        { 'type' => 'data',    'key' => 'hasperl',                                       'value' => Cpanel::FindBin::findbin( 'perl', 'path' => [ '/usr/bin', '/usr/local/bin' ] ) ? 1 : 0 },
        { 'type' => 'data',    'key' => 'haspear',                                       'value' => Cpanel::FindBin::findbin( 'pear', 'path' => [ '/usr/bin', '/usr/local/bin' ] ) ? 1 : 0 },
        { 'type' => 'data',    'key' => 'hasclamav',                                     'value' => -x Cpanel::Binaries::path("clamd")                                             ? 1 : 0 },
        { 'type' => 'data',    'key' => 'hasrails',                                      'value' => Cpanel::FindBin::findbin('rails')                                              ? 1 : 0 },
        { 'type' => 'data',    'key' => 'is_dnssec_supported',                           'value' => Cpanel::DNSSEC::Available::dnssec_is_available()                               ? 1 : 0 },
        { 'type' => 'data',    'key' => 'has_modenv',                                    'value' => Cpanel::ConfigFiles::Apache::modules::is_supported('mod_env')                  ? 1 : 0 },
        { 'type' => 'data',    'key' => 'has_modpassenger',                              'value' => -e $PASSENGER_APPS_PATH                                                        ? 1 : 0 },
        { 'type' => 'data',    'key' => 'allowcpsslinstall',                             'value' => $cpconf_ref->{allowcpsslinstall}                                               ? 1 : 0 },
        { 'type' => 'data',    'key' => 'ccs_installed',                                 'value' => Cpanel::DAV::Provider::installed() eq 'CCS'                                    ? 1 : 0 },
    ];
    my $postmaster = Cpanel::DbUtils::find_postmaster();
    if ($postmaster) {
        push @$keyref, { 'type' => 'command', 'key' => [ $postmaster, '--version' ] };
    }

    # cache may be built before mysql is installed. For example, EA4 installs
    # universal-hooks/multi_pkgs/transaction/ea-__WILDCARD__/010-purge_cache.pl
    # and EA4 is submitted before mysql on fresh install.
    my $mysqld = Cpanel::DbUtils::find_mysqld();
    if ( defined $mysqld ) {
        push @$keyref, { 'type' => 'command', 'key' => [ $mysqld, '--version' ] };
    }

    Cpanel::GlobalCache::Build::build_cache( 'cpanel', $keyref );

    return 1;
}

1;
