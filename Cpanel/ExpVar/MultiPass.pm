package Cpanel::ExpVar::MultiPass;

# cpanel - Cpanel/ExpVar/MultiPass.pm              Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel                         ();
use Cpanel::Config::Httpd::EA4     ();
use Cpanel::Config::LoadCpConf     ();
use Cpanel::Config::LoadCpUserFile ();
use Cpanel::DB::Utils              ();
use Cpanel::DB::Prefix::Conf       ();
use Cpanel::DIp::MainIP            ();
use Cpanel::Encoder::Tiny          ();
use Cpanel::ExpVar::Cache          ();
use Cpanel::ExpVar::Utils          ();
use Cpanel::Binaries               ();
use Cpanel::Locale                 ();
use Cpanel::MagicRevision          ();
use Cpanel::NAT                    ();
use Cpanel::PwCache                ();
use Cpanel::Quota                  ();
use Cpanel::Reseller::Override     ();
use Cpanel::Services::Enabled      ();
use Cpanel::SpamAssassin::Config   ();    # checked on every page in webmail, so perlcc in
use Cpanel::StatCache              ();
use Cpanel::GreyList::Config       ();
use Cpanel::GlobalCache            ();
use Cpanel::Dovecot::Solr          ();
use Cpanel::Themes::Get            ();
use Cpanel::Features::Utils        ();
use Cpanel::API::DAV               ();
use Cpanel::License::CompanyID     ();

my $locale;

my %TAKES_ARG;

BEGIN {
    %TAKES_ARG = map { $_ => 1 } (
        'BRANDINGIMG',
        'BRLANG',
        'CONFIF',
        'CONF',
        'CPDATA',
        'CPERROR',
        'CPFLAGS',
        'CPVAR',
        'ENV',
        'HASCHILDNODE',
        'HASMODULE',
        'HASROLE',
        'LANG',
        'MAGICREVISION',
        'NVDATA',
        'SERVICEPROVIDED',
        'exists_in_cpanel',
        'exists_in_webmail',
        'experimental',
        'is_feature_enabled',
    );
}

sub _exists {
    return -e $_[0];
}

sub _is_experimental {
    my $app_name = shift;
    _deprecated_expvar( 'experimental', 'is_feature_enabled' );
    return _is_feature_enabled($app_name);
}

sub _is_feature_enabled {
    my $app_name = shift;
    require Cpanel::FeatureFlags::Cache;
    return Cpanel::FeatureFlags::Cache::is_feature_enabled($app_name);
}

sub _deprecated_expvar {
    my ( $oldvar, $newvar ) = @_;

    my $template = '%s ExpVar is deprecated and will be removed in a future release, use %s ExpVar in all new code.';

    require Cpanel::Deprecation;
    Cpanel::Deprecation::warn_deprecated_with_replacement( $oldvar, $newvar, $template );
    return;
}

sub _safer_exists {
    my ( $path, $root ) = @_;
    return 0 if !$path || !$root;
    require Cwd;

    my $full_path = Cwd::abs_path("$root/$path");
    if ( $full_path =~ /^\Q$root\E/ ) {    # no traversals
        return _exists($full_path) ? 1 : 0;
    }
    return 0;
}

my %expansions = (
    BRANDINGIMG => sub {
        my $arg = shift;
        require Cpanel::Branding::Lite;
        return Cpanel::Encoder::Tiny::safe_html_encode_str( Cpanel::Branding::Lite::_image( $arg, 1 ) );
    },
    BRLANG => sub {
        my $arg = shift;
        $locale ||= Cpanel::Locale->get_handle();
        return join( '<br />', split( /\s+/, Cpanel::Encoder::Tiny::safe_html_encode_str( $locale->makevar($arg) ) ) );
    },

    # CONFIF is for parsing IFs in dynamicui.conf
    CONFIF => sub {
        return ( $Cpanel::CONF{ $_[0] } || 'disable' ) eq 'disable' ? 0 : 1;
    },

    CONF => sub {
        return ( ( $Cpanel::CONF{ $_[0] } || '' ) eq 'disable' ? 0 : Cpanel::Encoder::Tiny::safe_html_encode_str( defined $Cpanel::CONF{ $_[0] } ? $Cpanel::CONF{ $_[0] } : '' ) );
    },
    CPDATA => sub {
        my $arg = shift;
        return (
            index( $arg, 'MAX' ) == 0 && !$Cpanel::CPDATA{$arg}
            ? ( $arg eq 'MAXPARK' || $arg eq 'MAXADDON'                                  ? 0                     : 'unlimited' )
            : Cpanel::Encoder::Tiny::safe_html_encode_str( defined $Cpanel::CPDATA{$arg} ? $Cpanel::CPDATA{$arg} : '' )
        );
    },
    CPERROR => sub {
        my $arg = shift;
        return Cpanel::Encoder::Tiny::safe_html_encode_str( defined $Cpanel::CPERROR{$arg} ? $Cpanel::CPERROR{$arg} : '' );
    },
    CPFLAGS => sub {
        my $arg = shift;
        return Cpanel::Encoder::Tiny::safe_html_encode_str( defined $Cpanel::CPFLAGS{$arg} ? $Cpanel::CPFLAGS{$arg} : '' );
    },
    CPVAR => sub {
        my $arg = shift;
        return Cpanel::Encoder::Tiny::safe_html_encode_str( defined $Cpanel::CPVAR{$arg} ? $Cpanel::CPVAR{$arg} : '' );
    },
    ENV => sub {
        my $arg = shift;
        return Cpanel::Encoder::Tiny::safe_html_encode_str( $ENV{$arg} );
    },
    HASMODULE => sub {
        my $arg = shift;
        return Cpanel::StatCache::cachedmtime( '/usr/local/cpanel/Cpanel/' . $arg . '.pm' ) ? 1 : 0;
    },
    HASROLE => sub {
        require Cpanel::Server::Type::Profile::Roles;
        return Cpanel::Server::Type::Profile::Roles::is_role_enabled( $_[0] );
    },
    HASCHILDNODE => \&_has_child_node,
    LANG         => sub {
        my $arg = shift;
        $locale ||= Cpanel::Locale->get_handle();
        return $locale->makevar($arg);
    },
    MAGICREVISION => sub {
        my $arg = shift;
        return Cpanel::MagicRevision::calculate_theme_relative_magic_url($arg);
    },
    NVDATA => sub {
        my $arg = shift;
        require Cpanel::NVData;
        return Cpanel::Encoder::Tiny::safe_html_encode_str( Cpanel::NVData::_get($arg) || '' );
    },
    SERVICEPROVIDED => sub {
        my ($arg) = @_;
        require Cpanel::Services::Enabled;
        return Cpanel::Services::Enabled::is_provided($arg);
    },
    abshomedir        => sub { return $Cpanel::abshomedir; },
    any_stats_enabled => sub {
        my @stats_programs = qw(
          analog
          awstats
          webalizer
        );

        for (@stats_programs) {
            return 1 if !$Cpanel::CONF{"skip$_"};
        }
        return '';
    },
    appname      => sub { return $Cpanel::appname; },
    authuser     => sub { return $Cpanel::authuser; },
    basedir      => \&Cpanel::ExpVar::Utils::get_basedir,
    basefile     => \&Cpanel::ExpVar::Utils::get_basefile,
    basefilename => \&Cpanel::ExpVar::Utils::get_basefilename,
    binlog       => sub {
        return Cpanel::ExpVar::Utils::chomped_adminrun( 'cpmysql', 'CHECKBINLOG' );
    },
    brandingpkg => sub {
        require Cpanel::Branding::Lite::Package;
        return Cpanel::Branding::Lite::Package::_getbrandingpkg();
    },
    dbowner => sub {
        return Cpanel::DB::Utils::username_to_dbowner($Cpanel::user);
    },
    dbownerprefix => sub {
        my $dbowner_prefix = '';
        if ( ( exists $Cpanel::ExpVar::Cache::VARCACHE{'$dbprefix'} && $Cpanel::ExpVar::Cache::VARCACHE{'$dbprefix'} ) || Cpanel::DB::Prefix::Conf::use_prefix() ) {
            $Cpanel::ExpVar::Cache::VARCACHE{'$dbprefix'} = 1;    # Store calculated value
            my $cpuserdata     = Cpanel::Config::LoadCpUserFile::load($Cpanel::user);
            my $dbowner_cpuser = $Cpanel::ExpVar::Cache::VARCACHE{'$dbowner'} || $cpuserdata->{'DBOWNER'};

            require Cpanel::DB::Prefix;
            $dbowner_prefix = Cpanel::DB::Prefix::username_to_prefix($dbowner_cpuser);
            chomp($dbowner_prefix);

            $Cpanel::ExpVar::Cache::VARCACHE{'$dbowner'} = $dbowner_prefix;    # Store calculated value
            $dbowner_prefix .= '_';
        }
        return $dbowner_prefix;
    },
    dbprefix           => \&Cpanel::DB::Prefix::Conf::use_prefix,
    disk_quota_is_full => sub {
        my ( $used, $limit ) = Cpanel::Quota::displayquota(
            {
                bytes           => 1,
                include_sqldbs  => 0,
                include_mailman => 0,
            }
        );

        return ( $limit && ( $used >= $limit ) ) ? 1 : 0;
    },
    exists_in_cpanel => sub {
        my $path  = shift;
        my $theme = $Cpanel::CPDATA{'RS'} || Cpanel::Themes::Get::cpanel_default_theme();
        return _safer_exists( $path, "/usr/local/cpanel/base/frontend/$theme" );
    },
    exists_in_webmail => sub {
        my $path  = shift;
        my $theme = $Cpanel::CPDATA{'RS'} || Cpanel::Themes::Get::webmail_default_theme();
        return _safer_exists( $path, "/usr/local/cpanel/base/webmail/$theme" );
    },
    file_restoration_enabled => sub { return ( ( -e '/var/cpanel/config/backups/metadata_disabled' ) ? 0 : 1 ); },
    formdump                 => sub {
        my $str = '';
        foreach ( keys %Cpanel::FORM ) {
            $str .= "$_ = $Cpanel::FORM{$_}\n";
        }
        return $str;
    },
    hasdovecotsolr            => sub { return ( Cpanel::Dovecot::Solr::is_installed() && Cpanel::Services::Enabled::is_enabled('cpanel-dovecot-solr') ) ? 1 : 0 },
    hasanonftp                => sub { return ( ( -e '/var/cpanel/noanonftp' ) ? 0 : 1 ); },
    hasexim                   => sub { return Cpanel::Services::Enabled::is_enabled('exim') },
    hasftp                    => sub { return Cpanel::Services::Enabled::is_enabled('ftp') },
    hascpdavd                 => sub { return Cpanel::GlobalCache::data( 'cpanel', 'hascpdavd' ) },
    hasclamav                 => sub { return Cpanel::GlobalCache::data( 'cpanel', 'hasclamav' ) },
    hasautoconfig             => sub { return 1; },
    hascloudlinux             => \&Cpanel::ExpVar::Utils::has_cloudlinux,
    hasdedicatedip            => \&Cpanel::ExpVar::Utils::hasdedicatedip,
    hasgem                    => sub { return Cpanel::GlobalCache::data( 'cpanel', 'hasgem' ) },
    hasmoddeflate             => sub { return Cpanel::GlobalCache::data( 'cpanel', 'hasmoddeflate' ) },
    hasmodproxy               => sub { return Cpanel::GlobalCache::data( 'cpanel', 'hasmodproxy' ) },
    haspear                   => sub { return Cpanel::GlobalCache::data( 'cpanel', 'haspear' ) },
    hasperl                   => sub { return Cpanel::GlobalCache::data( 'cpanel', 'hasperl' ) },
    display_cpanel_doclinks   => sub { return Cpanel::GlobalCache::data( 'cpanel', 'display_cpanel_doclinks' ) },
    display_cpanel_promotions => sub { return Cpanel::GlobalCache::data( 'cpanel', 'display_cpanel_promotions' ) },
    haspostgres               => \&Cpanel::ExpVar::Utils::haspostgres,
    haspureftp                => sub { return ( ( -e "/usr/sbin/pure-ftpd" || -e "/usr/local/sbin/pure-ftpd" ) ? 1 : 0 ); },
    hasrails                  => sub { return Cpanel::GlobalCache::data( 'cpanel', 'hasrails' ) },
    hasunzip                  => sub { return -x Cpanel::Binaries::path('unzip') ? 1 : 0; },
    hasvalidshell             => sub {
        return ( ( ( Cpanel::PwCache::getpwuid_noshadow($>) )[8] ) !~ /noshell$/ ) ? 1 : 0;
    },
    haszip   => sub { return -x Cpanel::Binaries::path('zip') ? 1 : 0; },
    hostname => sub { require Cpanel::Hostname; return Cpanel::Hostname::gethostname() },
    homedir  => sub {
        return $Cpanel::homedir;
    },
    httphost                  => sub { return $Cpanel::httphost; },
    ip                        => sub { return Cpanel::ExpVar::Utils::get_public_ip() },
    is_mod_security_installed => sub { return Cpanel::GlobalCache::data( 'cpanel', 'has_modsecurity_installed' ) },
    is_greylisting_enabled    => \&Cpanel::GreyList::Config::is_enabled,
    is_sandbox                => sub {
        return -e '/var/cpanel/dev_sandbox' ? 1 : 0;
    },
    is_mail_account              => sub { return $Cpanel::authuser ne $Cpanel::user ? 1 : 0 },
    is_cpdavd_enabled            => sub { return Cpanel::GlobalCache::data( 'cpanel', 'hascpdavd' ) },
    is_solr_enabled              => sub { return Cpanel::GlobalCache::data( 'cpanel', 'hassolr' ) },
    market_has_enabled_providers => sub {
        return Cpanel::GlobalCache::data( 'cpanel', 'market_has_enabled_providers' );
    },
    is_twofactorauth_sec_policy_enabled => sub {
        %Cpanel::CONF = Cpanel::Config::LoadCpConf::loadcpconf() if !(%Cpanel::CONF);
        return $Cpanel::CONF{'SecurityPolicy::TwoFactorAuth'} ? 1 : 0;
    },
    is_ea4             => \&Cpanel::Config::Httpd::EA4::is_ea4,
    is_nat             => \&Cpanel::NAT::is_nat,
    is_support_enabled => sub {
        require Cpanel::YAML;
        require Cpanel::Branding::Lite;
        my $branding_dir = Cpanel::Branding::Lite::_get_contactinfodir();
        if ( -f "$branding_dir/contactinfo.yaml" ) {
            my $yaml = Cpanel::YAML::LoadFile("$branding_dir/contactinfo.yaml");
            return $yaml->{'contacttype'} eq 'disable' ? 0 : 1;
        }

        return 0;
    },
    isallowedssl => sub {

        #Does the account have the right privileges?
        %Cpanel::CONF = Cpanel::Config::LoadCpConf::loadcpconf() if !(%Cpanel::CONF);
        my $result = ( $Cpanel::CONF{'allowcpsslinstall'} ne '0' ) ? 1 : 0;
        return $result;
    },
    isarchiveuser => sub { return index( $Cpanel::authuser, '_archive@' ) == 0 ? 1 : 0; },
    hasboxtrapper => sub {
        return 0                                                 if index( $Cpanel::authuser, '_archive@' ) == 0;
        %Cpanel::CONF = Cpanel::Config::LoadCpConf::loadcpconf() if !(%Cpanel::CONF);
        return ( $Cpanel::CONF{'skipboxtrapper'} eq '1' ) ? 0 : 1;
    },
    isoverridelogin => sub {

        # This variable tells only if the current user is logged in by override with reseller or root password.
        return ( ( $ENV{'CPANEL_EXTERNAL_AUTH'} || Cpanel::Reseller::Override::is_overriding() ) ? 1 : 0 );    #TEMP_SESSION_SAFE
    },

    #displays whm in cpanel
    isreseller => sub {
        return ( $Cpanel::isreseller ? 1 : 0 );                                                                #TEMP_SESSION_SAFE
    },

    #displays create support ticket in whm
    isdirectcustomer => sub {
        return Cpanel::License::CompanyID::is_cpanel_direct();
    },

    #displays drop down account xfer in cpanel
    isresellerlogin => sub {
        return ( ( !$ENV{'CPANEL_EXTERNAL_AUTH'} && $Cpanel::isreseller || Cpanel::Reseller::Override::is_overriding() ) ? 1 : 0 );    #TEMP_SESSION_SAFE
    },

    is_invite_sub_enabled => sub {
        %Cpanel::CONF = Cpanel::Config::LoadCpConf::loadcpconf() if !(%Cpanel::CONF);
        return $Cpanel::CONF{'invite_sub'} ? 1 : 0;
    },
    isresold => sub {
        return ( ( $Cpanel::CPDATA{'OWNER'} eq "" || $Cpanel::CPDATA{'OWNER'} eq "0" || $Cpanel::CPDATA{'OWNER'} eq "root" ) ? 0 : 1 );
    },
    lang => sub {
        $locale ||= Cpanel::Locale->get_handle();
        return $locale->get_language_tag();
    },
    local_ip => sub {
        return Cpanel::ExpVar::Utils::get_local_ip();
    },
    locale => sub {
        $locale ||= Cpanel::Locale->get_handle();
        return $locale->get_language_tag();
    },
    mainhttpdport => sub { require Cpanel::Config::Httpd::IpPort; return Cpanel::Config::Httpd::IpPort::get_main_httpd_port() },
    mainserverip  => \&Cpanel::DIp::MainIP::getmainserverip,
    mainip        => \&Cpanel::DIp::MainIP::getmainip,
    mysql_sane    => sub {
        Cpanel::ExpVar::Utils::initialize_mysql_version_varcache();
        return $Cpanel::ExpVar::Cache::VARCACHE{'$mysql_sane'};
    },
    mysql_sane_errmsg => sub {
        Cpanel::ExpVar::Utils::initialize_mysql_version_varcache();
        return $Cpanel::ExpVar::Cache::VARCACHE{'$mysql_sane_errmsg'};
    },
    mysqlrunning => sub {
        my $alive;
        if ( $Cpanel::CPCACHE{'mysql'}{'cached'} ) {
            if ( defined $Cpanel::CPCACHE{'mysql'}{'ALIVE'} ) {
                $alive = $Cpanel::CPCACHE{'mysql'}{'ALIVE'};
            }
        }
        if ( !defined $alive ) {
            $alive = Cpanel::ExpVar::Utils::chomped_adminrun( 'cpmysql', 'ALIVE' );
        }
        if ( $Cpanel::CPERROR{$Cpanel::context} ) {
            $alive = "0";
        }
        return $alive;
    },
    mysqlversion => sub {
        Cpanel::ExpVar::Utils::initialize_mysql_version_varcache();
        return $Cpanel::ExpVar::Cache::VARCACHE{'$mysqlversion'};
    },
    parent_version => sub {
        return Cpanel::GlobalCache::data( 'cpanel', 'version_parent' );
    },
    pgrunning => sub {
        if ( $Cpanel::CPCACHE{'postgres'} && $Cpanel::CPCACHE{'postgres'}{'ISRUNNING'} && ( keys %{ $Cpanel::CPCACHE{'postgres'}{'ISRUNNING'} } )[0] ) {
            return '1';
        }
        else {
            return Cpanel::ExpVar::Utils::chomped_adminrun( 'postgres', 'PING' );
        }
    },
    random               => sub { return $ENV{DISABLE_EXPVAR_RANDOM} ? 1 : int( rand(1000000) ); },
    spamassassin_enabled => \&_spamassassin_enabled,
    sslhttpdport         => sub { require Cpanel::Config::Httpd::IpPort; return Cpanel::Config::Httpd::IpPort::get_ssl_httpd_port(); },
    theme                => sub { return $Cpanel::CPDATA{'RS'}; },
    user                 => sub { return $Cpanel::user; },
    version              => sub {
        return Cpanel::GlobalCache::data( 'cpanel', 'version_display' );
    },
    experimental       => \&_is_experimental,
    is_feature_enabled => \&_is_feature_enabled,
    has_team_license   => sub {
        require Cpanel::Server::Type;
        return Cpanel::Server::Type::has_feature('teams');
    },
    team_user => sub {
        return defined $ENV{TEAM_USER} ? 1 : 0;
    },
    is_delegated_mailman => sub {
        require Cpanel::Mailman::Delegates;
        ( undef, my $hasdelegated ) = Cpanel::Mailman::Delegates::has_delegated_mailman_lists($Cpanel::authuser);
        return $hasdelegated && index( $Cpanel::authuser, "_archive@" ) != 0;
    },
);

sub _has_child_node {
    require Cpanel::LinkedNode::Worker::Storage;
    return !!Cpanel::LinkedNode::Worker::Storage::read( \%Cpanel::CPDATA, $_[0] );
}

sub _spamassassin_enabled {
    return !!Cpanel::SpamAssassin::Config::who_enabled();
}

# This variable limits the search length for partial expansion matches.
# IE: $haszipxyzzy is a vaild expansion to 1xyzzy, and to determine this, the code must
# test all the partial matches until it finds $haszip.
# If an expansion that exceeds this limit is added, the limit must be increased to match.
my $maximum_substring_expansion = 15;

# Similar to the previous variable, this is the minimum expansion size.
my $minimum_substring_expansion = 2;

sub has_expansion {
    if ( length $_[0]->{expansion} ) {
        if ( ref $expansions{ $_[0]->{expansion} } && _arg_matches( $_[0] ) ) {
            return 1;
        }
        elsif ( _has_substring_expansion( $_[0] ) ) {
            return 1;
        }
    }
    return 0;
}

# If the expansion takes an argument, returns true only when argument is provided
# if the expansion doesn't take an argument, returns true onl when an argument is not provided
# An argument of an empty string is false in all cases.
sub _arg_matches {
    return !( length( $_[0]->{arg} ) xor $TAKES_ARG{ $_[0]->{expansion} } );
}

# If the token had an argument, start looking for the same token without any argument.
# Then repeatedly shorten the expansion looking for non-argument expansion matches.
sub _has_substring_expansion {
    my ($token) = @_;
    my $expansion_size = length( $token->{expansion} ) - ( defined $token->{arg} ? 0 : 1 );
    $expansion_size = $maximum_substring_expansion if ( $expansion_size > $maximum_substring_expansion );
    while ( $expansion_size >= $minimum_substring_expansion ) {
        my $test_expansion = substr( $token->{expansion}, 0, $expansion_size );
        if ( ref $expansions{$test_expansion} && !$TAKES_ARG{$test_expansion} ) {
            $token->{expansion} = $test_expansion;                                # put the correct expansion name
            $token->{arg}       = undef;
            $token->{extra}     = substr( $token->{raw}, $expansion_size + 1 );
            return 1;
        }
        $expansion_size--;
    }
    return 0;
}

# Note: It’s up to the caller to check has_expension before
# calling expand
#
# $_[0] = $token
# $_[1] = $detaint_coderef
sub expand {
    my $expanded = $expansions{ $_[0]->{expansion} }->( $_[0]->{arg} );
    $expanded = $_[1]->($expanded) if defined $_[1];
    return $Cpanel::ExpVar::Cache::VARCACHE{ $_[0]->{raw} } = $expanded . ( defined $_[0]->{extra} ? $_[0]->{extra} : '' );
}

1;
