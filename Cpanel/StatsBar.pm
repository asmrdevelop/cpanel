package Cpanel::StatsBar;

# cpanel - Cpanel/StatsBar.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;
no warnings;    ## no critic qw(ProhibitNoWarnings)

use Cpanel::API                         ();
use Cpanel::Quota                       ();
use Cpanel::Hostname                    ();
use Cpanel::ExpVar::Utils               ();
use Cpanel::Math::Bytes                 ();
use Cpanel::ArrayFunc                   ();
use Cpanel::Locale                      ();
use Cpanel::Quota::Constants            ();
use Locale::Maketext::Utils::MarkPhrase ();

use Cpanel::MysqlFE  ();
use Cpanel::Postgres ();

our $VERSION = 1.7;

use constant ONE_MiB => 1024**2;

my $mysqldb_count_cache;
my $postgresdb_count_cache;

## both of these are referenced in Cpanel::API::StatsBar
our $rSTATS;
our %ROWCOUNTERS;

my $locale;

sub api2_getrowcounter {
    my %CFG = @_;
    return [ { 'name' => $CFG{'rowcounter'}, 'value' => int $ROWCOUNTERS{ $CFG{'rowcounter'} } } ];
}

sub api2_setrowcounter {
    my %CFG = @_;
    if ( ( !exists $CFG{'rowcountervalue'} || $CFG{'rowcountervalue'} eq '' ) && exists $ROWCOUNTERS{ $CFG{'rowcounter'} } ) { $CFG{'rowcountervalue'} = $ROWCOUNTERS{ $CFG{'rowcounter'} } }
    return [ { 'name' => $CFG{'rowcounter'}, 'value' => ( $ROWCOUNTERS{ $CFG{'rowcounter'} } = int $CFG{'rowcountervalue'} ) } ];
}

sub api2_rowcounter {
    my %CFG = @_;
    my @RSD;
    if ( ++$ROWCOUNTERS{ $CFG{'rowcounter'} } % 2 == 0 ) {
        push( @RSD => { 'rowtype' => 'odd' } );
    }
    else {
        push( @RSD => { 'rowtype' => 'even' } );
    }
    return @RSD;
}

## DEPRECATED!
sub api2_stat {
    my %CFG    = @_;
    my $result = Cpanel::API::_execute( "StatsBar", "get_stats", \%CFG );
    return $result->data();
}

my $allow_demo = { allow_demo => 1 };

our %API = (
    stat          => { csssafe => 1, allow_demo => 1 },
    rowcounter    => $allow_demo,
    setrowcounter => $allow_demo,
    getrowcounter => $allow_demo,
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

sub _countsqldbs {
    return _count_mysql_dbs() + _count_postgresql_dbs() || 0;
}

sub clear_cache {
    undef $mysqldb_count_cache;
    undef $postgresdb_count_cache;
    undef $Cpanel::StatsBar::rSTATS;
    if ( $INC{'Cpanel/DomainLookup.pm'} ) {
        Cpanel::DomainLookup::reset_caches();
    }
    return;
}

sub _count_mysql_dbs {
    return $mysqldb_count_cache if defined $mysqldb_count_cache;
    return 0                    if $Cpanel::user eq 'cpanel';      # x3 branding edit session
    require Cpanel::MysqlFE::DB;
    return ( $mysqldb_count_cache = Cpanel::MysqlFE::DB::countdbs() );
}

sub _count_postgresql_dbs {
    return $postgresdb_count_cache if defined $postgresdb_count_cache;
    return 0                       if $Cpanel::user eq 'cpanel';         # x3 branding edit session
    require Cpanel::DbUtils;
    if ( Cpanel::DbUtils::find_psql() ) {
        require Cpanel::Postgres::DB;
        return ( $postgresdb_count_cache = Cpanel::Postgres::DB::countdbs() );
    }
    return 0;
}

sub _getbwlimit {
    return Cpanel::Math::Bytes::to_mib( $Cpanel::CPDATA{'BWLIMIT'} );
}

my $email_stats;
my $email_stats_user;

sub _get_email_stats {
    require Cpanel::StatsBar::Mail;
    undef $email_stats if $email_stats_user && $email_stats_user ne $Cpanel::user;
    $email_stats_user = $Cpanel::user;
    return $email_stats ||= Cpanel::StatsBar::Mail::create();
}

sub _count_filters {
    return _get_email_stats()->get_filters_count();
}

sub _get_list_disk_usage {
    return _get_email_stats()->get_lists_disk_usage();
}

sub _countlists {
    return _get_email_stats()->get_lists_count();
}

sub _count_forwarders {
    return _get_email_stats()->get_forwarders_count();
}

sub _count_autoresponders {
    return _get_email_stats()->get_autoresponders_count();
}

sub _countpops_novalidate {
    return _get_email_stats()->get_pops_count();
}

# NB: For now we put total bytes used--local PLUS remote--into the email
# stats because that works easily for v88’s case where there is only ever at
# most one remote node. Once we implement another remote node type we’ll
# need to rethink this. (cf. COBRA-11012)
sub _get_total_bytes_used {
    return int( _get_email_stats()->get_total_bytes_used() );
}

sub _get_total_bytes_limit {
    return int( ( $Cpanel::CPDATA{'DISK_BLOCK_LIMIT'} || 0 ) * Cpanel::Quota::Constants::BYTES_PER_BLOCK() );
}

# Since lists and sql databases are not included in system quota,
# the max space for them is the remaining system quota the user has.
#
# If quota is disabled, we return 0 since
# 0 is unlimited in this context and will display
# and infinity and preserve prior behavior
#
# This however leaves the edge case of "what to do" when we have 0 or negative disk quota left.
# As such, the determination of inf or 0 should be made higher up in the stack, as it knows whether
# the total disk quota is inf or not.
sub _listspace {
    my $left = ( _get_total_bytes_limit() - _get_total_bytes_used() );
    return $left > 0 ? $left : 0;
}

sub _listspace_clamped {
    my ( $finder_sub, $total_bytes ) = @_;
    my $tot = int( $finder_sub->() );
    my $rem = int( _listspace() );
    return Cpanel::ArrayFunc::min( $tot + $rem, int($total_bytes) );
}

sub _sql_max {
    if ( $Cpanel::CPDATA{'MAXSQL'} eq 'unlimited' ) {
        return $Cpanel::CPDATA{'MAXSQL'};
    }
    else {
        return ( Cpanel::ExpVar::Utils::haspostgres() ? 2 : 1 ) * $Cpanel::CPDATA{'MAXSQL'};    # Multiply by two since this is the total and MAXSQL allows MySQL *and* PostgreSQL.
    }
}

sub _load_stats_ref {
    my ($disk_bw_units) = @_;

    my $disk_bw_use_bytes = ( $disk_bw_units || q<> ) eq 'bytes';
    my $total_bytes       = _get_total_bytes_limit();

    $rSTATS = {
        'subdomains' => {
            'module'          => 'SubDomain',
            'feature'         => 'subdomains',
            '_count'          => \&Cpanel::SubDomain::countsubdomains,                                                                                                      # PPI NO PARSE -- 'module' will load this
            '_max'            => $Cpanel::CPDATA{'MAXSUB'},
            'zeroisunlimited' => 0,
            'phrase'          => Locale::Maketext::Utils::MarkPhrase::translatable('Subdomains'),
            near_limit_phrase => Locale::Maketext::Utils::MarkPhrase::translatable('You are using [numf,_1] of [numf,_2] available [numerate,_2,subdomain,subdomains].'),
            maxed_phrase      => Locale::Maketext::Utils::MarkPhrase::translatable('You are using your maximum allotment ([numf,_1]) of subdomains.'),
            role              => 'WebServer'
        },
        'autoresponders' => {
            '_count'          => \&_count_autoresponders,
            '_max'            => 0,
            'zeroisunlimited' => 1,
            'phrase'          => Locale::Maketext::Utils::MarkPhrase::translatable('Auto Responders'),
            near_limit_phrase => Locale::Maketext::Utils::MarkPhrase::translatable('You are using [numf,_1] of [numf,_2] available [numerate,_2,autoresponder,autoresponders].'),
            maxed_phrase      => Locale::Maketext::Utils::MarkPhrase::translatable('You are using your maximum allotment ([numf,_1]) of autoresponders.'),
        },
        'parkeddomains' => {
            'module'          => 'Park',
            'feature'         => 'parkeddomains',
            '_count'          => \&Cpanel::Park::_countparked,                                                                                                       # PPI NO PARSE -- 'module' will load this
            '_max'            => $Cpanel::CPDATA{'MAXPARK'},
            'zeroisunlimited' => 0,
            'phrase'          => Locale::Maketext::Utils::MarkPhrase::translatable('Parked Domains'),
            near_limit_phrase => Locale::Maketext::Utils::MarkPhrase::translatable('You are using [numf,_1] of [numf,_2] available [numerate,_2,alias,aliases].'),
            maxed_phrase      => Locale::Maketext::Utils::MarkPhrase::translatable('You are using your maximum allotment ([numf,_1]) of aliases.'),
            role              => { match => 'any', roles => [qw(WebServer MailReceive)] }
        },
        'addondomains' => {
            'module'          => 'Park',
            'feature'         => 'addondomains',
            '_count'          => \&Cpanel::Park::_countaddons,                                                                                                              # PPI NO PARSE -- 'module' will load this
            '_max'            => $Cpanel::CPDATA{'MAXADDON'},
            'zeroisunlimited' => 0,
            'phrase'          => Locale::Maketext::Utils::MarkPhrase::translatable('Addon Domains'),
            near_limit_phrase => Locale::Maketext::Utils::MarkPhrase::translatable('You are using [numf,_1] of [numf,_2] available addon [numerate,_2,domain,domains].'),
            maxed_phrase      => Locale::Maketext::Utils::MarkPhrase::translatable('You are using your maximum allotment ([numf,_1]) of addon domains.'),
            role              => 'WebServer'
        },
        'sqldatabases' => {
            '_count'          => \&Cpanel::StatsBar::_countsqldbs,
            '_max'            => \&_sql_max,
            'zeroisunlimited' => 0,
            'phrase'          => Locale::Maketext::Utils::MarkPhrase::translatable('All SQL Databases'),
            near_limit_phrase => Locale::Maketext::Utils::MarkPhrase::translatable('You are using [numf,_1] of [numf,_2] available [asis,SQL] [numerate,_2,database,databases].'),
            maxed_phrase      => Locale::Maketext::Utils::MarkPhrase::translatable('You are using your maximum allotment ([numf,_1]) of [asis,SQL] databases.'),
        },
        'mysqldatabases' => {
            '_count'          => \&Cpanel::StatsBar::_count_mysql_dbs,
            '_max'            => $Cpanel::CPDATA{'MAXSQL'},                                                                                                               # MAXSQL is the setting for MySQL and PostgreSQL databases individually
            'zeroisunlimited' => 0,
            'phrase'          => Locale::Maketext::Utils::MarkPhrase::translatable('Databases'),
            near_limit_phrase => Locale::Maketext::Utils::MarkPhrase::translatable('You are using [numf,_1] of [numf,_2] available [numerate,_2,database,databases].'),
            maxed_phrase      => Locale::Maketext::Utils::MarkPhrase::translatable('You are using your maximum allotment ([numf,_1]) of databases.'),
            role              => 'MySQLClient',
        },
        'postgresqldatabases' => {
            '_count'          => \&Cpanel::StatsBar::_count_postgresql_dbs,
            '_max'            => $Cpanel::CPDATA{'MAXSQL'},                                                                                                                                 # MAXSQL is the setting for MySQL and PostgreSQL databases individually
            'zeroisunlimited' => 0,
            'phrase'          => Locale::Maketext::Utils::MarkPhrase::translatable('[asis,PostgreSQL] Databases'),
            near_limit_phrase => Locale::Maketext::Utils::MarkPhrase::translatable('You are using [numf,_1] of [numf,_2] available [asis,PostgreSQL] [numerate,_2,database,databases].'),
            maxed_phrase      => Locale::Maketext::Utils::MarkPhrase::translatable('You are using your maximum allotment ([numf,_1]) of [asis,PostgreSQL] databases.'),
            role              => 'PostgresClient',
        },
        'diskusage' => {
            'module' => 'Quota',
            '_count' => sub {
                my $bytes = _get_total_bytes_used();
                $disk_bw_use_bytes ? $bytes : int( Cpanel::Math::Bytes::to_mib($bytes) );
            },
            '_max'            => $disk_bw_use_bytes ? $total_bytes : int( Cpanel::Math::Bytes::to_mib($total_bytes) ),
            'units'           => 'MB',
            'normalized'      => 1,
            'zeroisunlimited' => 1,
            'phrase'          => Locale::Maketext::Utils::MarkPhrase::translatable('Disk Space Usage'),
            near_limit_phrase => Locale::Maketext::Utils::MarkPhrase::translatable('You are using [format_bytes,_1] of the [format_bytes,_2] of storage available to you.'),
            maxed_phrase      => Locale::Maketext::Utils::MarkPhrase::translatable('You are using your maximum storage allotment, [format_bytes,_1].'),
        },

        'filesusage' => {
            'module'          => 'Quota',
            'condition'       => "expvar:\$CONF{'file_usage'}",
            '_count'          => \&Cpanel::Quota::_getfilesused,
            '_max'            => \&Cpanel::Quota::_getfileslimit,
            'normalized'      => 1,
            'zeroisunlimited' => 1,
            'phrase'          => Locale::Maketext::Utils::MarkPhrase::translatable('File Usage'),
        },
        'cachedpostgresdiskusage' => {
            'module'          => 'Postgres',
            'feature'         => 'postgres',
            'condition'       => 'expvar:$haspostgres',
            '_count'          => \&Cpanel::Postgres::_cacheddiskusage,                                               # PPI NO PARSE -- 'module' will load this
            '_max'            => sub { _listspace_clamped( \&Cpanel::Postgres::_cacheddiskusage, $total_bytes ) },
            'zeroisunlimited' => $total_bytes ? 0 : 1,
            'units'           => 'MB',
            'phrase'          => Locale::Maketext::Utils::MarkPhrase::translatable('PostgreSQL Disk Space'),
            role              => 'PostgresClient',
        },
        'cachedmysqldiskusage' => {
            'module'          => 'MysqlFE',
            '_count'          => \&Cpanel::MysqlFE::_cacheddiskusage,                                                # PPI NO PARSE -- 'module' will load this
            '_max'            => sub { _listspace_clamped( \&Cpanel::MysqlFE::_cacheddiskusage, $total_bytes ) },
            'zeroisunlimited' => $total_bytes ? 0 : 1,
            'phrase'          => Locale::Maketext::Utils::MarkPhrase::translatable('Database Disk Space'),
            'units'           => 'MB',
            role              => 'MySQLClient',
        },
        'cachedlistdiskusage' => {
            'condition'       => "expvar:!\$CONF{'skipmailman'}",
            '_count'          => \&_get_list_disk_usage,
            '_max'            => sub { _listspace_clamped( \&_get_list_disk_usage, $total_bytes ) },
            'zeroisunlimited' => $total_bytes ? 0 : 1,
            'phrase'          => Locale::Maketext::Utils::MarkPhrase::translatable('Mailing List Disk Space'),
            'units'           => 'MB',
            role              => 'MailReceive'
        },
        'postgresdiskusage' => {
            'module'          => 'Postgres',
            'feature'         => 'postgres',
            'condition'       => 'expvar:$haspostgres',
            '_count'          => \&Cpanel::Postgres::_diskusage,                                               # PPI NO PARSE -- 'module' will load this
            '_max'            => sub { _listspace_clamped( \&Cpanel::Postgres::_diskusage, $total_bytes ) },
            'zeroisunlimited' => $total_bytes ? 0 : 1,
            'units'           => 'MB',
            'phrase'          => Locale::Maketext::Utils::MarkPhrase::translatable('PostgreSQL Disk Space'),
            role              => 'PostgresClient',
        },
        'mysqldiskusage' => {
            'module'          => 'MysqlFE',
            '_count'          => \&Cpanel::MysqlFE::_diskusage,                                                # PPI NO PARSE -- 'module' will load this
            '_max'            => sub { _listspace_clamped( \&Cpanel::MysqlFE::_diskusage, $total_bytes ) },
            'zeroisunlimited' => $total_bytes ? 0 : 1,
            'phrase'          => Locale::Maketext::Utils::MarkPhrase::translatable('Database Disk Space'),
            'units'           => 'MB',
            'normalized'      => 0,
            role              => 'MySQLClient',
        },
        'bandwidthusage' => {
            'module'          => 'Stats',
            'feature'         => 'bandwidth',
            '_count'          => $disk_bw_use_bytes ? \&Cpanel::Stats::countbandwidth_bytes : \&Cpanel::Stats::countbandwidth,    # PPI NO PARSE -- 'module' will load this
            '_max'            => $disk_bw_use_bytes ? $Cpanel::CPDATA{'BWLIMIT'}            : \&_getbwlimit,
            'zeroisunlimited' => 1,
            'units'           => 'MB',
            'normalized'      => 1,
            'phrase'          => Locale::Maketext::Utils::MarkPhrase::translatable('Monthly Bandwidth Transfer'),
            near_limit_phrase => Locale::Maketext::Utils::MarkPhrase::translatable('You have transferred [format_bytes,_1] of your [format_bytes,_2] data allotment for this month.'),
            maxed_phrase      => Locale::Maketext::Utils::MarkPhrase::translatable('You have transferred your maximum allotment of data ([format_bytes,_1]) for this month.'),
            role              => 'WebServer'
        },
        'emailaccounts' => {
            'feature'         => 'popaccts',
            '_count'          => \&_countpops_novalidate,
            '_max'            => $Cpanel::CPDATA{'MAXPOP'},
            'zeroisunlimited' => 0,
            'phrase'          => Locale::Maketext::Utils::MarkPhrase::translatable('Email Accounts'),
            near_limit_phrase => Locale::Maketext::Utils::MarkPhrase::translatable('You are using [numf,_1] of [numf,_2] available email [numerate,_2,account,accounts].'),
            maxed_phrase      => Locale::Maketext::Utils::MarkPhrase::translatable('You are using your maximum allotment ([numf,_1]) of email accounts.'),
            role              => 'MailReceive'
        },
        'emailforwarders' => {
            '_count'          => \&_count_forwarders,
            '_max'            => 0,
            'zeroisunlimited' => 1,
            'phrase'          => Locale::Maketext::Utils::MarkPhrase::translatable('Email Forwarders'),
            role              => 'MailReceive'
        },
        'mailinglists' => {
            'condition'       => "expvar:!\$CONF{'skipmailman'}",
            'feature'         => 'lists',
            '_count'          => \&_countlists,
            '_max'            => $Cpanel::CPDATA{'MAXLST'},
            'zeroisunlimited' => 0,
            'phrase'          => Locale::Maketext::Utils::MarkPhrase::translatable('Mailing Lists'),
            near_limit_phrase => Locale::Maketext::Utils::MarkPhrase::translatable('You are using [numf,_1] of [numf,_2] available mailing [numerate,_2,list,lists].'),
            maxed_phrase      => Locale::Maketext::Utils::MarkPhrase::translatable('You are using your maximum allotment ([numf,_1]) of mailing lists.'),
            role              => 'MailReceive'
        },
        'emailfilters' => {
            '_count'          => \&_count_filters,
            '_max'            => 0,
            'zeroisunlimited' => 1,
            'phrase'          => Locale::Maketext::Utils::MarkPhrase::translatable('Email Filters'),
            role              => 'MailReceive'
        },
        'ftpaccounts' => {
            'module'          => 'API::Ftp',
            'condition'       => 'expvar:$hasftp',
            'feature'         => 'ftpaccts',
            '_count'          => \&Cpanel::API::Ftp::_countftp,                                                                                                                                                  # PPI NO PARSE -- 'module' will load this
            '_max'            => $Cpanel::CPDATA{'MAXFTP'},
            'zeroisunlimited' => 0,
            'phrase'          => Locale::Maketext::Utils::MarkPhrase::translatable('FTP Accounts'),
            near_limit_phrase => Locale::Maketext::Utils::MarkPhrase::translatable('You are using [numf,_1] of [numf,_2] available [output,abbr,FTP,File Transfer Protocol] [numerate,_2,account,accounts].'),
            maxed_phrase      => Locale::Maketext::Utils::MarkPhrase::translatable('You are using your maximum allotment ([numf,_1]) of [output,abbr,FTP,File Transfer Protocol] accounts.'),
            role              => 'FTP'
        },
        'shorthostname' => {
            'module' => 'Hostname',
            'value'  => \&Cpanel::Hostname::shorthostname,
            'phrase' => Locale::Maketext::Utils::MarkPhrase::translatable('Server Name'),
        },
        'hostname' => {
            'module' => 'Hostname',
            'value'  => \&Cpanel::Hostname::gethostname,
            'phrase' => Locale::Maketext::Utils::MarkPhrase::translatable('Hostname'),
        },
        'hostingpackage' => {
            'module' => 'PkgInfo',
            'value'  => \&Cpanel::PkgInfo::_strippedplanname,                                   # PPI NO PARSE -- 'module' will load this
            'phrase' => Locale::Maketext::Utils::MarkPhrase::translatable('Hosting Package'),
        },
        'sharedip' => {
            'condition' => 'expvar:!$hasdedicatedip',
            'value'     => 'expvar:$ip',
            'phrase'    => Locale::Maketext::Utils::MarkPhrase::translatable('Shared IP Address'),
        },
        'dedicatedip' => {
            'condition' => 'expvar:$hasdedicatedip',
            'value'     => 'expvar:$ip',
            'phrase'    => Locale::Maketext::Utils::MarkPhrase::translatable('Dedicated IP Address'),
        },
        'localip' => {
            'condition' => 'expvar:$is_nat',
            'value'     => 'expvar:$local_ip',
            'phrase'    => Locale::Maketext::Utils::MarkPhrase::translatable('Local IP Address'),
        },
        'operatingsystem' => {
            'module' => 'Serverinfo',
            'value'  => 'linux',
            'phrase' => Locale::Maketext::Utils::MarkPhrase::translatable('Operating System'),
        },
        'kernelversion' => {
            'module' => 'Serverinfo',
            'value'  => \&Cpanel::Serverinfo::_kernelver,                                      # PPI NO PARSE -- 'module' will load this
            'phrase' => Locale::Maketext::Utils::MarkPhrase::translatable('Kernel Version'),
        },
        'machinetype' => {
            'module' => 'Serverinfo',
            'value'  => \&Cpanel::Serverinfo::_machine,                                        # PPI NO PARSE -- 'module' will load this
            'phrase' => Locale::Maketext::Utils::MarkPhrase::translatable('Architecture'),
        },
        'apacheversion' => {
            'module' => 'Serverinfo',
            'value'  => \&Cpanel::Serverinfo::_apacheversion,                                  # PPI NO PARSE -- 'module' will load this
            'phrase' => Locale::Maketext::Utils::MarkPhrase::translatable('Apache Version'),
            'role'   => 'WebServer',
        },
        'perlversion' => {
            'module' => 'Serverinfo::Perl',
            'value'  => \&Cpanel::Serverinfo::Perl::version,                                   # PPI NO PARSE -- 'module' will load this
            'phrase' => Locale::Maketext::Utils::MarkPhrase::translatable('Perl Version'),
        },
        'perlpath' => {
            'module' => 'Serverinfo::Perl',
            'value'  => \&Cpanel::Serverinfo::Perl::path,                                      # PPI NO PARSE -- 'module' will load this
            'phrase' => Locale::Maketext::Utils::MarkPhrase::translatable('Path to Perl'),
        },
        'sendmailpath' => {
            'module' => 'Serverinfo',
            'value'  => \&Cpanel::Serverinfo::_sendmailpath,                                            # PPI NO PARSE -- 'module' will load this
            'phrase' => Locale::Maketext::Utils::MarkPhrase::translatable('Path to [asis,sendmail]'),
        },
        'mysqlversion' => {
            'module' => 'Serverinfo',
            'value'  => \&Cpanel::Serverinfo::_mysqlversion,                                              # PPI NO PARSE -- 'module' will load this
            'phrase' => Locale::Maketext::Utils::MarkPhrase::translatable('Database Software Version'),
            role     => 'MySQLClient',
        },
        'cpanelversion' => {
            'module' => 'Version',
            'value'  => \&Cpanel::Version::get_version_text,                                              # PPI NO PARSE -- 'module' will load this
            'phrase' => Locale::Maketext::Utils::MarkPhrase::translatable('[asis,cPanel] Version'),
        },
        'theme' => {
            'value'  => $Cpanel::CPDATA{'RS'},
            'phrase' => Locale::Maketext::Utils::MarkPhrase::translatable('Theme'),
        },
    };

    $rSTATS->{'emailac_counts'} = $rSTATS->{'emailaccounts'};    #bug work around in older version

    return;
}

1;
