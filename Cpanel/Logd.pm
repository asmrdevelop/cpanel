package Cpanel::Logd;

# cpanel - Cpanel/Logd.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# XXX TODO TODO TODO
#
# This code is very tightly coupled to libexec/cpanellogd; it should be able
# to run on its own. - look for references to the main:: namespace.
#----------------------------------------------------------------------

use cPstrict;
no warnings;    ## no critic qw(ProhibitNoWarnings) -- This is older code and has not been tested for warnings safety yet.

use Try::Tiny;

use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics

use Cwd                                  ();
use Cpanel::SafeFile                     ();
use Cpanel::PwCache::Cache               ();
use Cpanel::PwCache::Build               ();
use Cpanel::SafeDir::MK                  ();
use Cpanel::Config::LoadUserDomains      ();
use Cpanel::Config::LoadConfig           ();
use Cpanel::Config::LoadCpUserFile       ();
use Cpanel::Config::HasCpUserFile        ();
use Cpanel::Config::LoadCpConf           ();
use Cpanel::Config::Users                ();
use Cpanel::Config::User::Logs           ();
use Cpanel::DateUtils                    ();
use Cpanel::Hooks                        ();
use Cpanel::HttpUtils::Version           ();
use Cpanel::AccessIds::SetUids           ();
use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::ArrayFunc                    ();
use Cpanel::ConfigFiles                  ();
use Cpanel::FileUtils::TouchFile         ();
use Cpanel::Logd::BigLock                ();
use Cpanel::Logd::Dynamic                ();
use Cpanel::Bandwidth::BytesLogs         ();
use Cpanel::Bandwidth::Remote            ();
use Cpanel::BandwidthDB                  ();
use Cpanel::BandwidthDB::Constants       ();
use Cpanel::BandwidthDB::UserCache       ();
use Cpanel::BandwidthDB::RootCache       ();
use Cpanel::Carp                         ();
use Cpanel::Logs                         ();
use Cpanel::Logs::Find                   ();
use Cpanel::Logs::Truncate               ();
use Cpanel::BandwidthMgr                 ();
use Cpanel::NotifyDB                     ();
use Cpanel::Notify                       ();
use Cpanel::Locale                       ();
use Cpanel::Locale::Utils::User          ();
use Cpanel::Logd::Runner                 ();
use Cpanel::WildcardDomain               ();
use Cpanel::Server::PIDFile              ();
use Cpanel::SysQuota                     ();
use Cpanel::Binaries                     ();
use Cpanel::EximStats::Retention         ();
use Cpanel::Backup::Sync                 ();
use Cpanel::EximStats::ConnectDB         ();
use Cpanel::TimeHiRes                    ();
use Cpanel::ModSecurity::Logs            ();
use Cpanel::HttpUtils::ApRestart         ();

use Whostmgr::Transfers::AccountRestoration::Mutex ();

*loaduserLogConf = \&Cpanel::Config::User::Logs::load_users_log_config;
*resetfile       = \&Cpanel::Logs::Truncate::truncate_logfile;

my $logger;
my $reopenlock;
my $daysec = ( 24 * 60 * 60 );
my %cached_mount;
my $cached_mount_mtime;
my $symlink_dir = '/var/cpanel/cpanellogd.custom';    # no trailing slash
my $symlink_ext = 'cpanellogd';                       # no preceding dot
my $symlink_rgx = qr([.] $symlink_ext \z)xms;
my %CACHED_THIRDPARTY_LANG;
our $MAX_LOCKED_DB_RETRIES = 10;
our ( %STAT_CONF, $dcycle, $bwcycle );
our $dbh;
our $stats_log_obj;

Cpanel::Carp::enable();

### INIT #####
sub init {
    loadConfs();

    # Make certain we have up-to-date log directories.
    Cpanel::Logs::update_log_locations();
    return;
}
### INIT #####

#
# Create marker file to let the next run know that we need to process again
# when the blackout time is over.
sub reset_user_for_blackout {
    my ( $user, $type ) = @_;

    unlink("/var/cpanel/lastrun/$user/$type");
    return;
}

sub list_users_to_process {
    my ( $is_manual, $process_time, $type ) = @_;
    $type ||= 'stats';
    my @cpusers          = Cpanel::Config::Users::getcpusers();
    my @users_to_process = ();
    main::StatsLog( 50, "list_users_to_process ( manual = $is_manual , proc_time = $process_time, type = $type ) , cpusers = @cpusers" );

    my $cycle_time = ( $type eq 'stats' ? $dcycle : $bwcycle );

    if ($is_manual) {
        @users_to_process = map { [ $_, 0 ] } @cpusers;
    }
    else {
        foreach my $user (@cpusers) {
            my $lastrunstatsfile = "/var/cpanel/lastrun/$user/$type";

            my $mtime = ( stat($lastrunstatsfile) )[9];

            if ( !Whostmgr::Transfers::AccountRestoration::Mutex->new_if_not_exists($user) ) {
                main::StatsLog( 50, "User $user is being restored. Skipping …" );
            }
            else {
                my $mtime = ( stat($lastrunstatsfile) )[9];

                if ( !$mtime || $mtime <= $process_time || $mtime > ( $process_time + 2 * $cycle_time ) ) {
                    push @users_to_process, [ $user, $mtime || 0 ];
                }
                else {
                    main::StatsLog( 50, "User $user recently completed a '$type' update and is not due for processing yet." );
                }
            }
        }
    }

    # Always process oldest first
    return sort { $a->[1] <=> $b->[1] || $a->[0] cmp $b->[0] } @users_to_process;
}

sub prepare_apache_logs {
    my ($users_ref) = @_;
    my $has_changed = 0;
    my $domains     = Cpanel::Config::LoadUserDomains::loaduserdomains( undef, 0, 1 );
    my @logs;
    main::StatsLog( 50, "prepare_apache_logs() starting ( " . @{$users_ref} . " )" );
    Cpanel::Logs::Find::cache_log_locations();
    main::StatsLog( 50, "prepare_apache_logs() just did cache log locations" );

    my $pwcache_ref = Cpanel::PwCache::Build::fetch_pwcache();
    my $pwcache_map = { map { $_->[0] => $_ } @$pwcache_ref };
    my $cpconf      = Cpanel::Config::LoadCpConf::loadcpconf();

    # If we are not in conserve_memory mode and using piped logs,
    # we will need to flush the domlog filehandles before we archive
    # the logs. Some data could be sitting in the splitlogs buffer.
    if ( !-e '/var/cpanel/conserve_memory' && _using_piped_logs($cpconf) ) {
        _SIGHUP_splitlogs();
    }

    foreach my $u ( @{$users_ref} ) {
        main::StatsLog( 50, "prepare_apache_logs() handling logs for $u->[0]" );
        my ( $user, $lastruntime ) = @{$u};
        my $homedir = $pwcache_map->{$user}->[7];
        my $uid     = $pwcache_map->{$user}->[2];
        my $gid     = $pwcache_map->{$user}->[3];

        my ( $archivelogs, $remoldarchivedlogs ) = Cpanel::Config::User::Logs::load_users_log_config( $pwcache_map->{$user}, $cpconf );
        my $procdesc = find_process_type( $archivelogs, time );

        # This changes the incoming list.
        $u = [ $user, $lastruntime, $gid, $homedir, $archivelogs, $remoldarchivedlogs, $procdesc->{'type'}, $uid ];

        @logs = grep { should_process_log( $_->{'logfile'}, $lastruntime ) } Cpanel::Logs::list_logs_to_process( @{ $domains->{$user} || [] } );

        # if time for truncation, set up file move and update the name in list.
        my $change_count = Cpanel::Logs::pre_process_logs( $procdesc, \@logs, $homedir, $uid, $gid );

        # I need to get the @logs and modify the logfile name and keep flag to match
        # how it was left on disk.

        # If any changed, restart Apache
        if ( 0 != $change_count ) {
            $has_changed = 1;
            tear_down_loglinkage( $user, $gid, \@logs );
        }

    }
    main::StatsLog( 50, "prepare_apache_logs() has changed = $has_changed" );

    if ($has_changed) {
        restart_apache_if_necessary();
    }

    Cpanel::Logs::Find::cache_log_locations();

    foreach my $u ( @{$users_ref} ) {
        my ( $user, $lastruntime, $gid, $homedir, $archivelogs, $remoldarchivedlogs, $procdesctype, $uid ) = @{$u};

        # Trading time for space
        @logs = grep { should_process_log( $_->{'logfile'}, $lastruntime ) } Cpanel::Logs::list_logs_to_process( @{ $domains->{$user} || [] } );

        # This will force correction of the linkage even if we have nothing to process.
        # if user was terminated since the processing list started, we need to ignore this.
        if ( defined $homedir and '' ne $homedir and -d $homedir ) {
            restore_loglinkage( $user, $uid, $gid, $homedir, \@logs );
        }
    }
    return;
}

sub log_desc_from_list {
    my ($u) = @_;
    my $desc;
    @{$desc}{qw/user mtime gid homedir archivelogs remoldarchivedlogs postprocess uid/} = @{$u};
    return $desc;
}

#checklog section ------------------------------
sub scanlogs {
    my ($is_manual) = @_;

    $0 = 'cpanellogd - scanning logs';

    if ( !$is_manual && main::is_during_blackout() ) {
        main::StatsLog( 1, "Blackout hours in force, interrupt log processing before backing up access logs." );
        return;
    }
    else {
        main::StatsLog( 50, "Blackout hours clear, continuing with log processing." );
    }

    my $starttimer = time();

    Cpanel::PwCache::Build::init_passwdless_pwcache();    #speed up our getpwnams inside the loop

    my $nowtime      = time();
    my $diff         = $nowtime % $dcycle;
    my $process_time = $nowtime - ( $diff < $dcycle / 2 ? $dcycle : $diff );

    my $ucnt = my @users_to_process = list_users_to_process( $is_manual, $process_time, 'stats' );
    main::StatsLog( 50, "Found $ucnt users to process.. " );
    prepare_apache_logs( \@users_to_process );

    Cpanel::PwCache::Cache::pwmksafecache();

    my $biglock;
  PROCESS_USER:
    foreach my $u (@users_to_process) {
        $biglock ||= Cpanel::Logd::BigLock->new();    # We need a big lock to ensure stats do not get processed while logs are being archived/rotated

        main::StatsLog( 50, "Handling logs for user $u->[0]" );
        main::handleStopRequest();
        my $desc    = log_desc_from_list($u);
        my $homedir = $desc->{'homedir'};
        my $user    = $desc->{'user'};

        # A manual run ignores blackout hours.
        if ( !$is_manual && main::is_during_blackout() ) {
            main::StatsLog( 1, "Log processing interrupted by Blackout hours on '$desc->{'user'}'" );
            reset_user_for_blackout( $desc->{'user'}, 'stats' );
            return;
        }

        if ( $desc->{'mtime'} ) {
            main::StatsLog( 5, "[update] $desc->{'user'}: $desc->{'mtime'} < $process_time" );
            main::StatsLog( 5, "Updating stats lastrun file" );
        }

        my $cpuser = _scanlog_loadcpuser( $user, $desc->{'gid'} );
        if ( !$cpuser ) {
            main::StatsLog( 1, "Unable to load user '$desc->{'user'}', skipping..." );
            next PROCESS_USER;
        }
        setAccessLogPerms( $desc->{'gid'}, $cpuser->{'DOMAIN'}, $cpuser->{'DOMAINS'} );
        if ( !create_lastrun_file( $user, 'stats' ) ) {
            next PROCESS_USER;
        }
        dologs( $desc, $cpuser, ( $desc->{'mtime'} == 0 ), $biglock );
    }
    $biglock->close() if $biglock;
    return 1;
}

sub scan_a_user_logs {
    my ( $user, $cpuser, $biglock ) = @_;
    die "Failed to acquire a biglock" if !$biglock;
    if ( !$cpuser || !scalar keys %{$cpuser} ) {
        main::StatsLog( 1, "User '$user' not loaded, processing skipped..." );
        return;
    }
    my @logs = ( [ $user, 0 ] );
    prepare_apache_logs( \@logs );
    my $desc = log_desc_from_list( $logs[0] );
    return dologs( $desc, $cpuser, 1, $biglock );
}

#
# Attempt to restart apache intelligently.
# Wait for up to 20 seconds to see if someone else restarts it.
#   - determines restart by whether the pid file is rewritten, or
#   - any bytes files for the listed domains are created
sub restart_apache_if_necessary {
    my ($domains_ar) = @_;

    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf();

    # Do extra check for piped logs because we want to avoid the 20 second
    #  in restart_apache_if_necessary
    if ( _using_piped_logs($cpconf) ) {
        _flush_http_logs($cpconf);
    }
    else {
        my $cutoff = time;

        # wait up to 20 seconds for someone else to restart
        foreach ( 1 .. 200 ) {
            Cpanel::TimeHiRes::sleep(0.1);
            my $pidtime = ( stat apache_paths_facade->dir_run() . '/httpd.pid' )[9];
            if ( defined $pidtime and $pidtime > $cutoff ) {

                # Apache has definitely restarted and we're good to go
                return;
            }
        }

        # No sign of restart, force it.
        _apache_restart();
    }

    # Assuming that the above does not return until the restart is complete.
    return;
}

sub scanbandwidth {
    my ( $is_manual, $exim_retention_days ) = @_;

    if ( !$is_manual && main::is_during_blackout() ) {
        main::StatsLog( 1, "Blackout hours in force, interrupt bandwidth processing before backing up access logs." );
        return;
    }
    else {
        main::StatsLog( 50, "Blackout hours clear, continuing with bandwidth processing." );
    }

    checkBwLimitedDir();
    checkBwUsageDir();

    $0 = 'cpanellogd - processing bandwidth';
    main::StatsLog( 0, "Processing bandwidth." );

    Cpanel::Hooks::hook(
        {
            'category' => 'Stats',
            'event'    => 'RunAll',
            'stage'    => 'pre',
        },
        {}
    );

    Cpanel::PwCache::Build::init_passwdless_pwcache();    #speed up our getpwnams inside the loop

    my $pwcache_ref = Cpanel::PwCache::Build::fetch_pwcache();
    my $pwcache_map = { map { $_->[0] => $_ } @$pwcache_ref };
    my %DOMAINS;
    my %BWLIMITS;

    my $nowtime      = time();
    my $diff         = $nowtime % $bwcycle;
    my $process_time = $nowtime - ( $diff < $bwcycle / 2 ? $bwcycle : $diff );
    my $ucnt         = my @users_to_process = list_users_to_process( $is_manual, $process_time, 'bandwidth' );
    main::StatsLog( 50, "Found $ucnt users to process.. " );

    my %user_domains = ();

    main::handleStopRequest();
    Cpanel::Logs::Find::cache_log_locations();

    # For each user to process, find and backup relevant domains.
    if (@users_to_process) {
        my $cpconf           = Cpanel::Config::LoadCpConf::loadcpconf();
        my $live_domains_ref = Cpanel::Config::LoadUserDomains::loaduserdomains( undef, 1 );
        my ( $gid,             $cpuser );
        my ( $did_http_backup, $did_pop_imap_backup ) = ( 0, 0 );
        foreach my $u (@users_to_process) {
            my $user  = $u->[0];    #user field
            my $mtime = $u->[1];

            # We have notified on timeout for this user, don't process until tomorrow.
            next if processing_blocked($user);
            main::handleStopRequest();

            $gid    = $pwcache_map->{$user}->[3];
            $cpuser = _scanlog_loadcpuser( $user, $gid );
            if ( !$cpuser ) {
                main::StatsLog( 1, "Unable to load user '$user', skipping bandwidth backup..." );
                next;
            }
            $BWLIMITS{$user} = $cpuser->{'BWLIMIT'};
            $DOMAINS{$user}  = $cpuser->{'DOMAIN'};
            my $my_domains = build_complete_domain_arrayref( $cpuser, $live_domains_ref );

            $user_domains{$user} = { 'domains' => $my_domains, 'mtime' => $mtime };

            $did_http_backup     = 1 if Cpanel::Logs::backup_http_bytes_logs($my_domains);
            $did_pop_imap_backup = 1 if Cpanel::Logs::backup_pop_imap_bytes_logs($user);
        }

        _flush_http_logs($cpconf)      if $did_http_backup;
        _flush_tailwatch_logs($cpconf) if $did_pop_imap_backup;

        Cpanel::Logs::Find::cache_log_locations();
    }
    @users_to_process = ();

    pre_process_eximstats();

    my $root_bw_cache;
    try {
        $root_bw_cache = Cpanel::BandwidthDB::RootCache->new_without_rebuild();
    }
    catch {
        # We don't want the rootcache brokenness to prevent cpanellogd from processing as it can always be rebuilt later
        main::StatsLog( 0, "Loading the root bandwidth cache database failed because of an error: $_" );
    };

    my $remote_user_bw_hr;

    # process bandwidth.
    my ( $gid, $homedir, $cpuser, $biglock );
    foreach my $user ( sort { $user_domains{$a}->{'mtime'} <=> $user_domains{$b}->{'mtime'} || $a cmp $b } keys %user_domains ) {
        my $my_domains = $user_domains{$user}->{'domains'};
        $gid     = $pwcache_map->{$user}->[3];
        $homedir = $pwcache_map->{$user}->[7];

        main::handleStopRequest();

        if ( !$is_manual && main::is_during_blackout() ) {
            main::StatsLog( 1, "Bandwidth processing interrupted by Blackout hours on '$user'" );
            reset_user_for_blackout( $user, "bandwidth" );
            $biglock->close() if $biglock;
            return;
        }

        #
        #  Since only cpanellogd updates bandwidth files we keep a big lock
        #  on the bandwidth directory when we are doing updates.  This prevents
        #  the expensive disk I/O needed to create/tear down the locks for each
        #  user all the time.
        #

        $biglock ||= Cpanel::Logd::BigLock->new();
        next if !create_lastrun_file( $user, 'bandwidth' );

        $remote_user_bw_hr ||= do {
            my ( $thismonth, $thisyear ) = _get_month_and_year( time() );

            Cpanel::Bandwidth::Remote::fetch_all_remote_users_bandwidth(
                $thismonth,
                $thisyear,
            );
        };

        my $remote_usage_bytes = $remote_user_bw_hr->{$user} // 0;

        try {
            updatebw( $user, $homedir, $gid, $DOMAINS{$user}, $BWLIMITS{$user}, $my_domains, $biglock, $root_bw_cache, $remote_usage_bytes );
        }
        catch {
            main::StatsLog( 0, "Processing bandwidth for the user '$user' failed due to an error: $_" );
        };
    }
    $biglock->close() if $biglock;

    main::handleStopRequest();

    try {
        cleaneximtables($exim_retention_days);
    }
    catch {
        main::StatsLog( 0, "Expunging old records from the eximstats database failed due to an error: $_" );
    };
    eval {
        $SIG{__DIE__} = 'DEFAULT';
        if ( defined($dbh) ) { $dbh->disconnect(); }
    };

    Cpanel::Hooks::hook(
        {
            'category' => 'Stats',
            'event'    => 'RunAll',
            'stage'    => 'post',
        },
        {}
    );
    return;
}

sub setupuserlogdir {
    my $homedir    = shift;
    my $user       = shift;
    my @statsprogs = qw( analog awstats webalizer webalizerftp );
    my $tmpdir     = "$homedir/tmp";

    if ( $> == 0 ) { die "setupuserlogdir cannot be run as root"; }

    if ( -e $tmpdir && !-d $tmpdir ) { unlink($tmpdir); }
    if ( !-e $tmpdir )               { mkdir( $tmpdir, 0755 ); }

    my @checkdirs = map { "$tmpdir/$_" } @statsprogs;

    foreach my $dir (@checkdirs) {
        if ( -e $dir && !-d $dir ) {
            unlink($dir);
        }

        if ( !-e $dir ) {
            mkdir( $dir, 0700 );
        }
        else {
            my $perm = ( stat $dir )[2] & 07777;
            if ( $perm != 0700 ) {
                chmod( 0700, $dir );
            }
        }
    }

    return;
}

sub last_run_of_month {
    my ( $time, $cycle_hrs ) = @_;

    # Count the whole last day, even if cycle time is less than that.
    return Cpanel::DateUtils::time_til_month_end($time) < ( $cycle_hrs < 24 ? 86400 : $cycle_hrs * 3600 );
}

#
# Figure out which processing type is needed for the current user.
# Expects an $archivelogs flag to tell whether archiving is needed.
# Returns a hash giving the post_processing 'type', and a force flag that tells
#  whether the processing should complete on this pass.
sub find_process_type {
    my ( $archivelogs, $time ) = @_;

    my $time_to_postprocess = _is_time_for_post_process($time);
    if ($archivelogs) {

        # If we're going to archive, do not rotate until it's time to
        return { type => 'userarchive', force => $time_to_postprocess };
    }
    elsif ($time_to_postprocess) {

        #TODO: Remove dependency on global.
        if ( $main::CPCONF{'keeplogs'} ) {
            return { type => 'rotate', force => 1 };
        }
        else {
            return { type => 'delete', force => 1 };
        }
    }

    return { type => 'rotate', force => 0 };
}

sub _is_time_for_post_process {
    my ($time) = @_;

    if ( !$time ) {

        # No need to localize as this should only error during development
        die "Implementer error: _is_time_for_post_process requires a epoch time";
    }

    #TODO: Remove dependency on global.
    if ( $main::CPCONF{'dumplogs'} ) {

        # “Delete each domain’s access logs after statistics are gathered” is enabled
        return 1;
    }

    #TODO: Remove dependency on global.
    elsif ( last_run_of_month( $time, $main::CPCONF{'cycle_hours'} ) ) {

        # “Keep log files at the end of the month” is disabled
        return 1;
    }
    return 0;
}

#
# Check for backup file in addition to log newer than process time.
# Return true if processing is needed, false otherwise.
sub should_process_log {
    my ( $file, $lasttime ) = @_;
    return -e Cpanel::Logs::backup_filename($file) || fileisnewerthan( $file, $lasttime );
}

#
# Process normal logs
# 1. Build webalizer # No longer done.
# 2. Retrieve log list for (www access, ssl access, ftp)
# 3. Process webalizer
# 4. Process analog
# 5. Process awstats
# 6. Process ftp stats with webalizer
# 7. Archive and rotate logs
sub dologs {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ( $desc, $cpuser_ref, $force, $biglock ) = @_;
    die "Failed to acquire a biglock" if !$biglock;
    my ( $user, $homedir, $lastruntime, $gid, $archivelogs, $remoldarchivedlogs, $postprocess, $uid ) = @{$desc}{qw/user homedir mtime gid archivelogs remoldarchivedlogs postprocess uid/};
    my ( $domain, $domainref ) = @{$cpuser_ref}{qw/DOMAIN DOMAINS/};

    main::StatsLog( 50, "starting dologs()" );

    if ( $main::CPCONF{'nocpbackuplogs'} ) {
        Cpanel::Backup::Sync::check_for_backups_requesting_pause();
    }

    $0 = "cpanellogd - setting up logs for $user";

    # Return if user is already meeting, or over their quota.
    return if ( !checkDiskSpaceOk( $user, $homedir ) );

    if ( !$domain || $domain =~ tr{ \r\n\t}{} ) {
        main::StatsLog( 0, "Invalid domain name for user: $user ($domain)" );
        return;
    }

    local $Cpanel::CPDATA{'LOCALE'} = Cpanel::Locale::Utils::User::get_user_locale( $user, $cpuser_ref );

    $0 = "cpanellogd - loading config for $user";

    main::StatsLog( 0, "Archive Status for $user: $archivelogs" );

    my %processed;
    my @logs    = grep { should_process_log( $_->{'logfile'}, $lastruntime ) } Cpanel::Logs::list_logs_to_process( $domain, @{ $domainref || [] } );
    my $ftp_log = Cpanel::Logs::find_ftplog($domain);

    my $has_new_logs = 0;
    if (@logs) {
        main::StatsLog( 5, "$user has a log file ($logs[0]->{'logfile'}) newer than last run time: $lastruntime" );
        $has_new_logs = 1;
    }
    my $process_ftp_log = $ftp_log ? should_process_log( $ftp_log, $lastruntime ) : 0;
    $has_new_logs ||= $process_ftp_log;

    my $locale     = Cpanel::Locale->get_handle();
    my $locale_tag = $locale->get_language_tag();
    foreach my $prog (qw(webalizer analog awstats)) {
        $CACHED_THIRDPARTY_LANG{ $locale_tag . '_' . $prog } ||= $locale->cpanel_get_3rdparty_lang($prog) || 'en';
    }

    my @DOMAINS_LIST      = ( ( ref $domainref ? ( @{$domainref} ) : () ), $domain );
    my $domains_list_text = scalar @DOMAINS_LIST . ' domains';

    if ( $has_new_logs || $force ) {

        # Modifies the state of @logs
        Cpanel::Logs::check_pre_process_state( $postprocess, \@logs );

        # Determine if any mtimes are new enough to process logs
        my %NEEDS_STATS_RUN;
        foreach my $desc (@logs) {
            my $access_log = $desc->{logfile};

            if ( fileisnewerthan( $access_log, $lastruntime ) ) {
                $NEEDS_STATS_RUN{'www'} = $access_log;
                last;
            }
        }
        if ( $process_ftp_log && fileisnewerthan( $ftp_log, $lastruntime ) ) {
            $NEEDS_STATS_RUN{'ftp'} = $ftp_log;
        }
        my $need_to_process_ftp_in_second_pass = 0;
        if ( grep { $_ } values %NEEDS_STATS_RUN ) {
            main::StatsLog( 0, "Processing $user, fork() required to drop privs with (domains:$domains_list_text)" );
            main::StatsLog( 5, "Stats run triggered by mtime on: " . join( ", ", values %NEEDS_STATS_RUN ) );
            if ( my $pid = fork() ) {
                $0 = "cpanellogd - waiting for child to process logs for $user";
                waitpid( $pid, 0 );
            }
            else {
                $0 = "cpanellogd - http logs for $user";

                Cpanel::AccessIds::SetUids::setuids( $uid, $gid ) || die "Failed to setuid to ($uid,$gid)";

                main::StatsLog( 0, "[setuid] $user (uid=$uid,gid=$gid)" );

                my $user_data = {
                    'lastruntime' => $lastruntime,
                    'user'        => $user,
                    'homedir'     => $homedir,
                    'maindomain'  => $domain,
                    'rALLDOMAINS' => $domainref,
                    'logfiledesc' => \@logs,
                };

                @processed{ map { $_->{logfile} } @logs } = ();
                _do_logs_for_user( $user_data, $cpuser_ref, $ftp_log, $process_ftp_log );

                exit;
            }
        }
        else {
            main::StatsLog( 0, "1 of 2: Skipping $user, no activity since $lastruntime [" . scalar localtime($lastruntime) . "] (domains:$domains_list_text)" );
            $need_to_process_ftp_in_second_pass = 1 if $process_ftp_log;
        }

        if ($process_ftp_log) {
            my $ftplog = Cpanel::Logs::prepare_ftplog_for_processing( $ftp_log, $domain );

            # case 77749: Unless its time to archive and delete the log
            # we need to set 'keep' so it is not archived and discarded
            # prematurely
            $ftplog->{'keep'} = _is_time_for_post_process( time() ) ? 0 : 1;
            push @logs, $ftplog;

        }

        $0 = "cpanellogd - archiving logs for $user";
        Cpanel::Logs::post_process_logs( $postprocess, \@logs, { archivedir => "$homedir/logs", user => $user, homedir => $homedir } );

        # Clean up ModSecurity logs, if any.

        my $success = 1;
        if ($archivelogs) {
            $success = Cpanel::ModSecurity::Logs::archive_logs($user);
        }
        if ($success) {
            Cpanel::ModSecurity::Logs::remove_modsecurity_logs($user);
            main::StatsLog( 1, "The system has archived any ModSecurity logs." );
        }
        else {
            main::StatsLog( 0, "The system is unable to archive ModSecurity logs for $user; probably out of quota" );
        }

        $0 = "cpanellogd - rotating logs for $user";
        if ( $postprocess eq 'userarchive' && $remoldarchivedlogs ) {
            Cpanel::Logs::remove_old_user_archives( "$homedir/logs", \@logs );
        }

        # if the user had NGINX and Apache logs:
        #    NGINX was handled above and a second pass should get Apache
        # if there are no NGINX logs: this could process any new apache traffic
        #    on top of the traffic we just archived, so only do 2nd pass on files that were not just %processed
        if ( $postprocess eq 'userarchive' ) {

            # UGMO 1 global internal: NGINX log can exist at this point so we need to drop it for this pass:
            local @Cpanel::Logs::Find::_default_log_locations = @Cpanel::Logs::Find::_default_log_locations;
            shift @Cpanel::Logs::Find::_default_log_locations;

            # UGMO 2 global internal: the cached _default_log_locations is also cached based on mtime so we need to drop it here too
            local @Cpanel::Logs::Find::_log_locations = @Cpanel::Logs::Find::_log_locations;
            shift @Cpanel::Logs::Find::_log_locations;

            my @logs = grep {
                my $file = $_->{logfile};
                !exists $processed{$file} && should_process_log( $file, $lastruntime )
            } Cpanel::Logs::list_logs_to_process( $domain, @{ $domainref || [] } );

            if (@logs) {

                # UGMO 3: pass one had this happen by the caller of dologs()
                setAccessLogPerms( $gid, $domain, $domainref || [] );
                prepare_apache_logs( [ [ $user, 0 ], ] );

                # UGMO 4: copy pasta due to all the variables involved here, could be a function with ike 20 arguments :(

                # Modifies the state of @logs
                Cpanel::Logs::check_pre_process_state( $postprocess, \@logs );

                main::StatsLog( 0, "Processing $user, fork() required to drop privs with (domains:$domains_list_text)" );
                main::StatsLog( 5, "Stats run triggered by mtime on: " . join( ", ", values %NEEDS_STATS_RUN ) );
                if ( my $pid = fork() ) {
                    $0 = "cpanellogd - waiting for child to process logs for $user (2)";
                    waitpid( $pid, 0 );
                }
                else {
                    $0 = "cpanellogd - http logs for $user (2)";

                    Cpanel::AccessIds::SetUids::setuids( $uid, $gid ) || die "Failed to setuid to ($uid,$gid)";

                    main::StatsLog( 0, "[setuid] $user (uid=$uid,gid=$gid)" );

                    my $user_data = {
                        'lastruntime' => $lastruntime,
                        'user'        => $user,
                        'homedir'     => $homedir,
                        'maindomain'  => $domain,
                        'rALLDOMAINS' => $domainref,
                        'logfiledesc' => \@logs,
                    };

                    @processed{ map { $_->{logfile} } @logs } = ();
                    _do_logs_for_user( $user_data, $cpuser_ref, $ftp_log, $need_to_process_ftp_in_second_pass );

                    exit;
                }

                Cpanel::Logs::post_process_logs( $postprocess, \@logs, { archivedir => "$homedir/logs", user => $user, homedir => $homedir } );
                Cpanel::Logs::remove_old_user_archives( "$homedir/logs", \@logs ) if $remoldarchivedlogs;
            }
            else {
                main::StatsLog( 0, "2 of 2: Skipping $user, no activity since $lastruntime [" . scalar localtime($lastruntime) . "] (domains:$domains_list_text)" );
            }
        }

        return 1;
    }
    else {
        main::StatsLog( 5, "$user has no log files newer than $lastruntime." );
        return 0;
    }
}

sub _do_logs_for_user {
    my ( $user_data, $cpuser_ref, $ftp_log, $process_ftp_log ) = @_;

    my ( $user, $homedir, $domain ) = @{$user_data}{qw/user homedir maindomain/};

    my %LOG_CONF = get_userLogConfig( $user, $homedir, $cpuser_ref, $domain, $user_data->{'rALLDOMAINS'} );    # Gather the user's statistics preferences.
    $user_data->{'rLOG_CONF'} = \%LOG_CONF;

    my $hook_info = {
        'category' => 'Stats',
        'event'    => 'RunUser',
        'stage'    => 'pre',
        'blocking' => 1,
    };

    my ( $pre_hook_result, $hook_msgs ) = Cpanel::Hooks::hook(
        $hook_info,
        $user_data,
    );

    if ( !$pre_hook_result ) {
        my $hooks_msg = int @{$hook_msgs} ? join "\n", @{$hook_msgs} : '';
        main::StatsLog( 0, qq{Stats::RunUser pre hook prevented stats processing for $user: $hooks_msg} );
        return;
    }

    setupuserlogdir( $homedir, $user );

    my %ALL_STATS_CONFIG           = %{ _get_all_stats_config() };
    my @AVAILABLE_STATS_PROCESSORS = sort keys %ALL_STATS_CONFIG;

    foreach my $stats_prog (@AVAILABLE_STATS_PROCESSORS) {
        if ( !$main::CPCONF{ 'skip' . $stats_prog } ) {
            try {
                _runStatsProgram(
                    'prog' => $stats_prog,    # program to run stats with
                    %$user_data,
                    %{ $ALL_STATS_CONFIG{$stats_prog} },
                );
            }
            catch {
                main::StatsLog( 0, "[dologs] Failed to process stats for $domain." );
            };
        }
    }
    if ($process_ftp_log) {
        my $ftp_log_name = "ftp.$domain";
        main::StatsLog( 5, "[webalizerftp] $user - $ftp_log_name" );

        my $applang = _cached_3rdparty_lang('webalizer');

        webalizerBrokenCheck("$homedir/tmp/webalizerftp");

        if ( lc( $LOG_CONF{ 'WEBALIZER-' . uc($domain) } ) eq 'yes' ) {
            my $webalizer = webalizerBin($applang);
            if ( length $webalizer ) {
                Cpanel::Logd::Runner::run(
                    'program' => $webalizer,
                    'args'    => [
                        '-F' => 'ftp',
                        '-N' => '10',
                        '-D' => "$homedir/tmp/webalizerftp/dns_cache.db",
                        '-R' => '250',
                        '-p',
                        '-n' => $ftp_log_name,
                        '-o' => "$homedir/tmp/webalizerftp",
                        $ftp_log
                    ],
                    'logger' => $stats_log_obj
                );
            }
            else {
                main::StatsLog( 5, "[webalizerftp] $user - The system did not process $ftp_log_name because the “webalizer” binary is missing or not executable." );
            }
        }
    }

    Cpanel::Hooks::hook(
        {
            'category' => 'Stats',
            'event'    => 'RunUser',
            'stage'    => 'post',
        },
        $user_data,
    );
    return;
}

#
# Send an email notifying the appropriate user that the bandwidth processing timed out.
sub bandwidth_timeout_notify {
    my ( $user, $domain, $type ) = @_;

    require Cpanel::Services::Log;
    my ( $cpanel_error_log_tail_status, $cpanel_error_log_tail_text ) = Cpanel::Services::Log::fetch_log_tail( $Cpanel::ConfigFiles::CPANEL_ROOT . '/logs/error_log', 300 );
    my ( $cpanel_stats_log_tail_status, $cpanel_stats_log_tail_text ) = Cpanel::Services::Log::fetch_log_tail( $Cpanel::ConfigFiles::CPANEL_ROOT . '/logs/stats_log', 300 );

    Cpanel::Notify::notification_class(
        'class'            => 'Logd::Notify',
        'application'      => 'cpanellogd-bandwidth_timeout-' . $domain,
        'interval'         => $daysec,
        'status'           => "Bandwidth Processing Timeout for $user",
        'constructor_args' => [
            'origin'                => 'Logd',
            'bandwidth_type'        => $type,
            'user'                  => $user,
            'user_domain'           => $domain,
            'cpanel_stats_log_path' => $Cpanel::ConfigFiles::CPANEL_ROOT . '/logs/stats_log',
            'cpanel_error_log_path' => $Cpanel::ConfigFiles::CPANEL_ROOT . '/logs/error_log',
            'attach_files'          => [
                { name => 'cpanel_stats_log_reverse_order_tail.txt', content => \$cpanel_stats_log_tail_text },
                { name => 'cpanel_error_log_reverse_order_tail.txt', content => \$cpanel_error_log_tail_text },
            ]

        ],
    );

    return 1;
}

#
# If we have sent a notification for this user within the last day
# return true.
sub processing_blocked {
    my ($user) = @_;
    return Cpanel::Notify::notify_blocked(
        app      => 'cpanellogd',
        status   => "Bandwidth Processing Timeout for $user",
        interval => $daysec,
    );
}

sub _is_real_file {
    my ($file) = @_;
    return '' ne $file && -f $file && -s _;
}

sub _save_bw_for_time_user_domain {
    my ( $bandwidth_db, $root_bw_cache, $now_ts, $user, $domain ) = @_;

    $bandwidth_db->write();

    my ( $thismonth, $thisyear ) = ( localtime($now_ts) )[ 4, 5 ];
    $thismonth++;
    $thisyear += 1900;

    my $total_ar = $bandwidth_db->get_bytes_totals_as_array(
        start     => "$thisyear-$thismonth",
        end       => "$thisyear-$thismonth",
        protocols => ['http'],
        domains   => [$domain],
        grouping  => [],
    );

    my $total_num = $total_ar->[0][0] || 0;

    main::StatsLog( 5, "[bytes] $user - subdomain: $domain (total: $total_num)" );

    if ($root_bw_cache) {
        my $user_id   = $root_bw_cache->get_or_create_id_for_user($user);
        my $domain_id = $root_bw_cache->get_or_create_id_for_domain($domain);
        try {
            $root_bw_cache->set_user_domain_year_month_bytes(
                $user_id,
                $domain_id,
                $thisyear,
                $thismonth,
                $total_num,
            );
        }
        catch {
            warn $_;
        };
    }

    return;
}

sub _get_month_and_year ($now) {
    my ( $thismonth, $thisyear ) = ( localtime($now) )[ 4, 5 ];
    $thismonth++;
    $thisyear += 1900;

    return ( $thismonth, $thisyear );
}

#
# Generate and process bandwidth information for the supplied user.
# 1. Process the known bytes files for the supplied user to generate bandwidth data.
#    - parse bytes files
#    - summarize data
#    - Write long-term summaries to text files
#    - remove/truncate old bytes files
# 2. Update the bandwidth cache
# 3. Handle bandwidth limits
#    - notify user if needed
#    - trigger the bwlimit processing with BandwidthMgr
#
sub updatebw {    ## no critic qw(Subroutines::ProhibitExcessComplexity Subroutines::ProhibitManyArgs)
    my ( $user, $homedir, $gid, $domain, $bwlimit, $domainref, $biglock, $root_bw_cache, $remote_usage_bytes ) = @_;

    die "Failed to acquire a biglock" if !$biglock;

    my $bwruntime = time();

    if ( $main::CPCONF{'nocpbackuplogs'} ) {
        Cpanel::Backup::Sync::check_for_backups_requesting_pause();
    }

    $0 = "cpanellogd - updating bandwidth for $user";
    main::StatsLog( 0, "Process bandwidth for $user" );
    main::StatsLog( 5, "Update Bandwidth for $user ($domain)" );

    my $safe_domain   = Cpanel::WildcardDomain::encode_wildcard_domain($domain);
    my $ftp_log       = Cpanel::Logs::find_ftplog($safe_domain);
    my $bytes_log     = Cpanel::Logs::find_byteslog_backup($safe_domain);
    my $popbytes_log  = Cpanel::Logs::find_popbyteslog_backup($user);
    my $imapbytes_log = Cpanel::Logs::find_imapbyteslog_backup($user);
    my $ftpbytes_log  = Cpanel::Logs::find_ftpbyteslog($safe_domain);

    my $max_file_xfer = ( 1024 * 1024 * 1024 * 9 );
    my $max_mail_xfer = ( 1024 * 1024 * 1024 * 8 );    # Maximum size we expect to be transfered in an IMAP or POP3 session

    main::StatsLog( 5, "[bytes] $user" );

    my $now = time;
    my ( $thismonth, $thisyear ) = _get_month_and_year($now);

    #
    #  Since only cpanellogd updates bandwidth files we keep a big lock
    #  on the bandwidth directory when we are doing updates.  This prevents
    #  the expensive disk I/O needed to create/tear down the locks for each
    #  user all the time.
    #

    my $bandwidth_db = Cpanel::BandwidthDB::get_writer($user);

    # For main domain
    if ( _is_real_file($bytes_log) ) {

        parsehttpbyteslog( $safe_domain, $bytes_log, $max_file_xfer, $bandwidth_db, $biglock )
          or bandwidth_timeout_notify( $user, $domain, 'http' );

        # Update the all type for this domain
        $bandwidth_db->write();

        _save_bw_for_time_user_domain( $bandwidth_db, $root_bw_cache, $now, $user, $domain );
    }

    # Don't need to update total for month, already taken into account.

    foreach my $ddomain ( @{$domainref} ) {
        next if $domain eq $ddomain;    # Already processed above.
        my $safe_ddomain = Cpanel::WildcardDomain::encode_wildcard_domain($ddomain);
        my $dbytes_log   = Cpanel::Logs::find_byteslog_backup($safe_ddomain);

        next unless _is_real_file($dbytes_log);

        parsehttpbyteslog( $safe_ddomain, $dbytes_log, $max_file_xfer, $bandwidth_db, $biglock )
          or bandwidth_timeout_notify( $user, $ddomain, 'http' );

        _save_bw_for_time_user_domain( $bandwidth_db, $root_bw_cache, $now, $user, $ddomain );
    }

    # All of the HTTP entries for all domains are all finished, so we can write
    # out the user http data at this point.

    if ( dbconnect() ) {
        parseeximlog( $user, $max_mail_xfer, $bandwidth_db, $biglock )
          or bandwidth_timeout_notify( $user, $domain, 'smtp' );
    }
    if ( _is_real_file($ftp_log) ) {
        parseftpbyteslog( $user, $ftp_log, $max_file_xfer, $bandwidth_db, $biglock )
          or bandwidth_timeout_notify( $user, $domain, 'ftp' );
    }
    if ( _is_real_file($popbytes_log) ) {
        parsebyteslog( $user, 'pop3', $popbytes_log, $max_mail_xfer, $bandwidth_db, $biglock )
          or bandwidth_timeout_notify( $user, $domain, 'pop3' );
    }
    if ( _is_real_file($imapbytes_log) ) {
        parsebyteslog( $user, 'imap', $imapbytes_log, $max_mail_xfer, $bandwidth_db, $biglock )
          or bandwidth_timeout_notify( $user, $domain, 'imap' );
    }

    # Now the user has all of the bandwidth calculated, so write out the all
    # case
    $bandwidth_db->write();

    my $this_month_by_domain_hr = $bandwidth_db->get_bytes_totals_as_hash(
        start    => "$thisyear-$thismonth",
        end      => "$thisyear-$thismonth",
        grouping => ['domain'],
    );

    if ($root_bw_cache) {
        try {
            my $user_id   = $root_bw_cache->get_or_create_id_for_user($user);
            my $domain_id = $root_bw_cache->get_or_create_id_for_domain($Cpanel::BandwidthDB::Constants::UNKNOWN_DOMAIN_NAME);

            $root_bw_cache->set_user_domain_year_month_bytes(
                $user_id,
                $domain_id,
                $thisyear,
                $thismonth,
                $this_month_by_domain_hr->{$Cpanel::BandwidthDB::Constants::UNKNOWN_DOMAIN_NAME} || 0,
            );
        }
        catch {
            warn $_;
        };
    }

    my $totalthismonth = Cpanel::ArrayFunc::sum( values %$this_month_by_domain_hr ) || 0;

    $remote_usage_bytes //= Cpanel::Bandwidth::Remote::fetch_remote_user_bandwidth(
        $user,
        $thismonth,
        $thisyear,
    );

    $totalthismonth += $remote_usage_bytes;

    try {
        Cpanel::BandwidthDB::UserCache::write( $user, $totalthismonth );
    }
    catch {
        warn $_;
    };

    main::StatsLog( 5, "[bytes] $user - limit: $bwlimit (total: $totalthismonth)" );

    logreset($ftpbytes_log) if $ftpbytes_log;

    # Do not check bandwidth limits.
    if ( $bwlimit <= 0 || -e '/var/cpanel/bwlimitcheck.disabled' ) {
        return;
    }

    # Check if soon to exceed limits.
    if ( $totalthismonth > 0 && $main::CPCONF{'emailusersbandwidthexceed'} ) {

        Cpanel::NotifyDB::loadnotify($user);
        my $notify_level = 0;

        # Mark all of the levels we've passed and store the highest
        foreach my $bwwarn (@Cpanel::BandwidthMgr::BWWARNLVLS) {
            next if ( !$main::CPCONF{ 'emailusersbandwidthexceed' . $bwwarn } );
            if ( $totalthismonth > ( ( $bwwarn / 100 ) * $bwlimit ) ) {
                next if ( Cpanel::NotifyDB::didnotify( $user, 'emailusersbandwidthexceed' . $bwwarn ) );
                Cpanel::NotifyDB::savenotify( $user, 'emailusersbandwidthexceed' . $bwwarn );
                $notify_level = $bwwarn if $bwwarn > $notify_level;
            }
            else {
                Cpanel::NotifyDB::clearnotify( $user, 'emailusersbandwidthexceed' . $bwwarn );
            }
        }

        # If we have exceeded some level, send 1 message (at the highest level)
        # unless we have already exceeded the limit. In that case the message is
        # sent later.
        if ( $notify_level && ( $bwlimit >= $totalthismonth ) ) {
            nooutputsystembg(
                '/usr/local/cpanel/bin/bwlimit_notify',
                $user, $domain, 1, $notify_level,
                sprintf( "%.2f", $bwlimit / ( 1024 * 1024 ) ),
                sprintf( "%.2f", $totalthismonth / ( 1024 * 1024 ) )
            );
        }
        Cpanel::NotifyDB::flushnotify($user);
    }

    # Send a message if the limit is actually exceeded.
    if ( $totalthismonth > $bwlimit ) {
        Cpanel::BandwidthMgr::enablebwlimit( $user, $safe_domain, $bwlimit, $totalthismonth, $main::CPCONF{'emailusersbandwidthexceed'}, $domainref );
    }
    else {
        Cpanel::BandwidthMgr::disablebwlimit( $user, $safe_domain, $bwlimit, $totalthismonth, $main::CPCONF{'emailusersbandwidthexceed'}, $domainref );
    }
    return;
}

sub getmonth {
    my $mon = ( localtime( time() ) )[4];
    $mon++;
    return $mon;
}

sub rotatelogs {
    my ($logsize);

    my $thresh_hold = 300;
    my $cpconf_hr   = Cpanel::Config::LoadCpConf::loadcpconf();
    if ( $cpconf_hr->{'rotatelogs_size_threshhold_in_megabytes'} ) {

        # decimals are OK (if not a little pointless) so no need for abs()
        if ( int( $cpconf_hr->{'rotatelogs_size_threshhold_in_megabytes'} ) >= 10 ) {
            $thresh_hold = int( $cpconf_hr->{'rotatelogs_size_threshhold_in_megabytes'} );
        }
        else {

            # $logger->info('cpanel config value for rotatelogs_size_threshhold_in_megabytes is less than 10, ignoring and using default');
            warn 'cpanel config value for rotatelogs_size_threshhold_in_megabytes is less than 10, ignoring and using default';
        }
    }

    my @logfiles = ( '/var/log/chkservd.log', '/var/cpanel/roundcube/log/errors', Cpanel::Logd::Dynamic::get_custom_logd_link_paths() );
    {

        # process any leftover backup files with data
        my @logdescs = Cpanel::Logs::make_logdesc_list( grep { -s $_ } Cpanel::Logs::make_backup_list(@logfiles) );
        Cpanel::Logs::post_process_logs( 'sysarchive', \@logdescs );
    }

    Cpanel::Logs::Find::cache_log_locations();

    # backup current log files
    my $limit      = 1024 * 1024 * $thresh_hold;
    my @logdescs   = Cpanel::Logs::make_logdesc_list( grep { -f $_ && -s _ >= $limit } @logfiles );
    my $change_cnt = Cpanel::Logs::pre_process_logs( { type => 'sysarchive', force => 0 }, \@logdescs, undef, undef, undef, $limit );

    # restart services (as needed)
    if ($change_cnt) {
        _flush_http_logs($cpconf_hr);
        if ( _using_piped_logs($cpconf_hr) ) {

            # Case 108785, when the logs are rotated apache has to restart.
            # _flush does not restart apache, so do it purposefully here.

            _apache_restart();
        }
        flush_cpsrvd();
        Cpanel::Logs::Find::cache_log_locations();
    }

    # process backup files and delete them
    Cpanel::Logs::post_process_logs( 'sysarchive', \@logdescs );

    return;
}

sub _using_piped_logs {
    my ($cpconf) = @_;
    return $cpconf->{'enable_piped_logs'} && Cpanel::HttpUtils::Version::get_apache_decimal_version() >= 2;
}

sub _flush_http_logs {
    my ($cpconf) = @_;

    if ( _using_piped_logs($cpconf) ) {
        _SIGHUP_splitlogs();
    }
    else {
        _apache_restart();
    }
    return;
}

sub _flush_tailwatch_logs {
    require Cpanel::Signal;

    # We used to send USR1, however that did not
    # cause tailwatchd to unblock inotify loop
    #
    # Since USR1 has been repurposed to do a hot restart
    # we now send HUP which causes the log file and
    # ensures the inotify loop unblocks and the flush
    # actually happens.
    #
    # For more information see the handler
    # code in
    # libexec/tailwatch/tailwatchd.pl
    return Cpanel::Signal::send_hup_tailwatchd();
}

sub _SIGHUP_splitlogs {
    require Cpanel::Kill;
    return Cpanel::Kill::killall( 'HUP', 'splitlogs' );
}

sub flush_cpsrvd {
    open my $fh, '<', Cpanel::Server::PIDFile::PATH() or return;
    chomp( my $pid = <$fh> );
    close $fh;

    return unless $pid;

    return kill 'HUP', $pid;
}

sub buildawconf {
    my ( $outputdir, $logfile, $domain, $maindomain, $domainref ) = @_;

    main::StatsLog( 3, "[buildawconf] $domain -> $outputdir" );

    # Build HostAliases line - parameter used to analyze referrer field
    my %host_aliases;
    foreach my $bdomain ( $domain, $maindomain, @{$domainref} ) {
        $bdomain = lc $bdomain;
        $bdomain =~ s/\s+//g;
        $host_aliases{$bdomain} = 1;
        if ( $bdomain !~ m/^www\./ && $bdomain !~ /^\*/ ) {
            $host_aliases{ 'www.' . $bdomain } = 1;
        }
    }
    my $domains = join( ' ', sort keys %host_aliases ) . ' localhost 127.0.0.1';

    my $dnslookup = 0;
    if ( $main::CPCONF{'awstatsreversedns'} ) {
        main::StatsLog( 3, "[buildawconf] reverse lookup enabled ($domain)" );
        $dnslookup = 1;
    }
    else {
        main::StatsLog( 3, "[buildawconf] reverse lookup disabled ($domain)" );
    }

    my $browserupdate = 0;
    if ( $main::CPCONF{'awstatsbrowserupdate'} ) {
        main::StatsLog( 3, "[buildawconf] browser update enabled ($domain)" );
        $browserupdate = 1;
    }
    else {
        main::StatsLog( 3, "[buildawconf] browserupdate disabled ($domain)" );
    }

    my $hasipfree = 0;
    eval {
        local $SIG{__DIE__} = 'DEFAULT';
        require Cpanel::GeoIPfree;    # PPI USE OK -- used for hasipfree
        $hasipfree = 1;
    };

    my $has_include = 0;
    if ( $STAT_CONF{'allow_awstats_include'} && -r $outputdir . '/awstats.conf.include' ) {
        main::StatsLog( 1, "[buildawconf] Using awstats.conf.include for $domain" );
        $has_include = 1;
    }

    my $safe_domain = Cpanel::WildcardDomain::encode_wildcard_domain($domain);
    if ( open my $awconf_default_fh, '<', '/usr/local/cpanel/etc/awstats.conf' ) {
        if ( open my $awconf_fh, '>', $outputdir . '/awstats.' . $safe_domain . '.conf' ) {
            my %AWCONF = (
                'DNSLOOKUP'     => $dnslookup,
                'BROWSERUPDATE' => $browserupdate,
                'LOGFILE'       => $logfile,
                'AWSTATSDIR'    => $outputdir,
                'DOMAINS'       => $domains,
                'DOMAIN'        => $domain
            );
            while ( my $line = readline $awconf_default_fh ) {
                $line =~ s/\%([^\%]+)\%/$AWCONF{$1}/g;
                next if ( !$hasipfree && $line =~ m/geoipfree/ );
                print {$awconf_fh} $line;
            }
            if ($has_include) {
                print {$awconf_fh} "Include \"${outputdir}/awstats.conf.include\"\n";
            }
            close $awconf_fh;
        }
        else {
            if ( -r $outputdir . '/awstats.' . $safe_domain . '.conf' && -s _ ) {
                main::StatsLog( 1, "[buildawconf] Failed to update ${outputdir}/awstats.${safe_domain}.conf: $!" );
                return 1;
            }
            main::StatsLog( 1, "[buildawconf] Failed to create ${outputdir}/awstats.${safe_domain}.conf: $!" );
            return;
        }
        close $awconf_default_fh;
    }
    else {
        main::StatsLog( 1, "[buildawconf] Failed to read default awstats.conf: $!" );
        return;
    }

    # If the logfile data does not exist
    if ( !-e $logfile || -z _ ) {
        main::StatsLog( 3, "[buildawconf] $domain has no log data" );
        return 1;
    }

    return 1;
}

sub clearoffset {
    my $file       = shift || return;
    my $offsetname = shift || '';
    my $offsetlock = Cpanel::SafeFile::safeopen( \*LOGFILET, ">", "${file}.offset${offsetname}" );
    if ($offsetlock) {
        print LOGFILET '0';
        Cpanel::SafeFile::safeclose( \*LOGFILET, $offsetlock );
    }
}

sub saveoffset {
    my $file       = shift || return;
    my $offsetname = shift || '';
    my $end        = tell(LOGFILE);
    Cpanel::SafeFile::safeclose( \*LOGFILE, $reopenlock );
    my $offsetlock = Cpanel::SafeFile::safeopen( \*LOGFILET, '>', "${file}.offset${offsetname}" );
    if ($offsetlock) {
        print LOGFILET $end;
        Cpanel::SafeFile::safeclose( \*LOGFILET, $offsetlock );
    }
}

sub reopenfileatoffset {
    my $file       = shift || return;
    my $offsetname = shift || '';
    my $size       = ( stat($file) )[7];
    my $offsetlock = Cpanel::SafeFile::safeopen( \*LOGFILET, '<', "${file}.offset${offsetname}" );

    my $start = 0;
    if ($offsetlock) {
        chomp( $start = <LOGFILET> );
        Cpanel::SafeFile::safeclose( \*LOGFILET, $offsetlock );
    }

    $reopenlock = Cpanel::SafeFile::safeopen( \*LOGFILE, '<', $file );
    if ($reopenlock) {
        if ( $size >= $start ) {
            seek( LOGFILE, $start, 0 );
        }
    }
    return;
}

sub sepxferlog {
    $0 = 'cpanellogd - seperating xferlog';
    main::StatsLog( 0, "[sepxferlog]" );

    my $usertodomain_ref = Cpanel::Config::LoadUserDomains::loadtrueuserdomains( undef, 1 );
    my $domaintouser_ref = Cpanel::Config::LoadUserDomains::loadtrueuserdomains();
    Cpanel::PwCache::Build::init_passwdless_pwcache();
    Cpanel::Logs::Find::cache_log_locations();

    my %FTPLOG;
    my $pwcache_ref = Cpanel::PwCache::Build::fetch_pwcache();
    foreach my $userinfo (@$pwcache_ref) {
        next
          if ( $userinfo->[2] <= 99
            || $userinfo->[0] eq 'nobody'
            || length( $userinfo->[7] ) < 5
            || !$userinfo->[7]
            || !$userinfo->[0]
            || !exists $usertodomain_ref->{ $userinfo->[0] } );

        my $ftp_log = Cpanel::Logs::find_ftplog( $usertodomain_ref->{ $userinfo->[0] } );
        $ftp_log ||= apache_paths_facade->dir_domlogs() . "/ftp.$usertodomain_ref->{ $userinfo->[0] }-ftp_log";
        $FTPLOG{ $userinfo->[7] } = $FTPLOG{ $userinfo->[0] } = $ftp_log;
    }

    my @XFERLOGS = ( '/var/log/xferlog', apache_paths_facade->dir_domlogs() . '/ftpxferlog' );
    my @FILE;
    my $lastlog = '';
    my ( $file, $authuser, $accessmode, $authenticated, $domain, $home );
    foreach my $xferlog (@XFERLOGS) {
        main::handleStopRequest();
        if ( !-e $xferlog ) {
            clearoffset( $xferlog, 'ftpsep' );    # Clean offset just in case
            next;
        }
        my $readlink = readlink($xferlog);
        next if ( $xferlog eq '/var/log/xferlog' && $readlink && $readlink =~ /domlogs\/ftpxferlog/ );
        reopenfileatoffset( $xferlog, 'ftpsep' );
        while (<LOGFILE>) {
            chomp;
            ( $file, $accessmode, $authuser, $authenticated ) = ( split( /\s+/, $_ ) )[ 8, 12, 13, 15 ];
            if ( $authuser && $authenticated && $accessmode eq 'r' ) {
                if ( $authuser =~ /\@/ ) {
                    $domain = ( split( /\@/, $authuser ) )[1];
                    if ( exists $FTPLOG{ $domaintouser_ref->{$domain} } ) {
                        if ( $lastlog ne $FTPLOG{ $domaintouser_ref->{$domain} } ) {
                            close(FTPLOG);
                            open( FTPLOG, '>>', $FTPLOG{ $domaintouser_ref->{$domain} } );
                        }
                        print FTPLOG $_ . "\n";
                        $lastlog = $FTPLOG{ $domaintouser_ref->{$domain} };
                        next;
                    }
                }
                elsif ( exists $FTPLOG{$authuser} ) {
                    if ( $lastlog ne $FTPLOG{$authuser} ) {
                        close(FTPLOG);
                        open( FTPLOG, '>>', $FTPLOG{$authuser} );
                    }
                    print FTPLOG $_ . "\n";
                    $lastlog = $FTPLOG{$authuser};
                    next;
                }
            }
            @FILE = split( /\//, $file );
          DIRLOOKUP:
            while ( scalar @FILE ) {
                pop @FILE;
                $home = join( '/', @FILE );
                if ( $FTPLOG{$home} ) {
                    if ( $lastlog ne $FTPLOG{$home} ) {
                        close(FTPLOG);
                        open( FTPLOG, '>>', $FTPLOG{$home} );
                    }
                    print FTPLOG $_ . "\n";
                    $lastlog = $FTPLOG{$home};
                    last DIRLOOKUP;
                }
            }
        }
        saveoffset( $xferlog, 'ftpsep' );
        if ( !$main::CPCONF{'keepftplogs'} ) {
            Cpanel::Logs::Truncate::truncate_logfile($xferlog);
            clearoffset( $xferlog, 'ftpsep' );
        }
    }
    close(FTPLOG);
    main::StatsLog( 0, "[sepxferlog] complete" );
    return;
}

sub _do_with_retry_on_locked {
    my ($statement) = @_;

    local $@;
    local $SIG{__DIE__} = 'DEFAULT';
    my ( $rows, $err );
    my $tries = 0;
    while ( $tries++ < $MAX_LOCKED_DB_RETRIES ) {
        $rows = eval { $dbh->do($statement) };

        if ($@) {
            $err = $@;

            if ( $MAX_LOCKED_DB_RETRIES > $tries && _error_is_locked( $err, $DBI::errstr ) ) {
                _sleep(1);
                next;
            }

            die;    # will propogate $@
        }
        else {
            last;
        }
    }

    return $rows;
}

sub _sleep {
    return sleep( $_[0] || 1 );
}

sub _error_is_locked {
    my ( $error, $dbi_error ) = @_;

    local $@;
    if ( eval { $error->isa('Cpanel::Exception::Database::Error') } ) {
        return $error->failure_is('SQLITE_LOCKED') ? 1 : 0;
    }
    elsif ( length $dbi_error && $dbi_error =~ m/^database is locked/ ) {
        return 1;
    }

    return 0;
}

sub geteximstats {
    my ( $user, $biglock ) = @_;
    die "Failed to acquire a biglock" if !$biglock;

    my %BYTES;
    main::StatsLog( 5, "Processing exim stats for $user...." );
    try {
        local $SIG{__DIE__} = 'DEFAULT';

        if ( !dbconnect() ) {
            main::StatsLog( 0, "Cannot connect to database.\n" );
            die;
        }

        my $quoted_user = $dbh->quote($user);

        # Locking is no longer needed since we have a Cpanel::Logd::BigLock on the whole
        # bandwidth processing

        # We setup which rows we are going to be processing by marking 'smtp.processed' to 1
        my $rows;
        try {
            $rows = _do_with_retry_on_locked("update smtp set processed='1' where transport_is_remote='1' and processed='0' and msgid IN (SELECT sends.msgid FROM sends INNER JOIN smtp ON (sends.msgid=smtp.msgid) WHERE smtp.transport_is_remote='1' and smtp.processed='0' and sends.user=$quoted_user); /* Cpanel::Logd::geteximstats - bandwidth processing */");
        }
        catch {
            local $@ = $_;
            my $error_message = $_ || $DBI::errstr;
            main::StatsLog( 0, "Database Error: $error_message\n" );
            die;
        };

        my $new_data;

        if ( $rows > 0 ) {
            main::StatsLog( 5, "$rows new rows for $user" );

            # We select all the data in the rows we have just marked for processing (smtp.processed=1)
            # We normalize the data to 5 minute blocks
            my $err;
            try {
                $new_data = $dbh->selectall_arrayref("select SUM(sends.size) as STEPSIZE, ( smtp.sendunixtime - ( smtp.sendunixtime % 300 ) ) as STEPTIME from smtp INNER JOIN sends ON (sends.msgid=smtp.msgid) where sends.size IS NOT NULL and sends.user=$quoted_user and smtp.processed='1' GROUP BY STEPTIME;");
            }

            # If we fail to select the data or get an invalid return we will reset rows we were going to
            # process so they can be processed later (if possible)
            catch {
                $err = $_;
                main::StatsLog( 0, "Failed to select eximstats data for $user: $err" );
            };

            if ($err) {
                try {
                    _do_with_retry_on_locked("update smtp set processed='0' where processed='1';");
                }
                catch {
                    local $@ = $_;
                    main::StatsLog( 0, "Failed to reset processed eximstats values to unprocessed while attempting to process eximstats for the user $user." );
                    die;
                };
            }

            # We mark which rows we have processed
            try {
                _do_with_retry_on_locked("update smtp set processed='2' where processed='1';");
            }
            catch {
                local $@ = $_;
                my $error_message = $_ || $DBI::errstr;
                main::StatsLog( 0, "Database Error: $error_message\n" );
                die;
            }
        }
        else {
            main::StatsLog( 5, "No new rows for $user" );
        }

        # Convert the data after we unlock the tables so we hold the lock for the least time possible
        %BYTES = map { $_->[1] => $_->[0] } @$new_data if $new_data;
    }
    catch {
        main::StatsLog( 0, "There was an error retrieving Eximstats information for the user $user: $_" );
    };

    main::StatsLog( 5, "...Done" );

    return \%BYTES;
}

sub pre_process_eximstats {

    # We do not count bandwidth for mailman, root, or -remote- so we can
    # avoid the expense of processing the rows for each user by pre-setting
    # smtp.processed to 2

    eval {
        if ( dbconnect() ) {
            $SIG{__DIE__} = 'DEFAULT';

            my $sql = "update smtp set processed='3' where transport_is_remote='1' and processed='0' and msgid IN (SELECT sends.msgid FROM sends INNER JOIN smtp ON (sends.msgid=smtp.msgid) WHERE smtp.transport_is_remote='1' and smtp.processed='0' and sends.user IN ('-remote-','root','mailman'));";
            _do_with_retry_on_locked($sql);
        }

    };
    if ($@) {
        main::StatsLog( 0, "There was an error pre-processing the eximstats database: $@" );
    }
    return;
}

sub cleaneximtables {
    my $exim_retention_days = shift;

    $exim_retention_days = Cpanel::EximStats::Retention::get_valid_exim_retention_days($exim_retention_days);
    if ($exim_retention_days) {    # To be safe, take zero to mean infinite retention.
                                   # (But note the UI disallows that, in any case.)
        print "==> Retention days: $exim_retention_days\n";
        eval {
            if ( dbconnect() ) {
                $SIG{__DIE__} = 'DEFAULT';

                my $day_seconds       = 24 * 60 * 60;
                my $retention_seconds = int( $day_seconds * $exim_retention_days );

                # no need to lock
                # We are deleting one more day back then what we normally delete when we run each user
                # This is being extra safe as the run should have happened many times before we get here anyways

                for my $table (qw[ smtp sends defers failures ]) {
                    my $sql = "delete from $table where ( strftime( '%s', 'now' ) - $retention_seconds ) > sendunixtime;";
                    _do_with_retry_on_locked($sql);
                }
            }
        };
    }
    return;
}

sub dbconnect {
    $dbh = Cpanel::EximStats::ConnectDB::dbconnect_no_rebuild();
    unless ($dbh) {
        warn 'Cannot connect: ' . $DBI::errstr;
        return 0;
    }
    return 1;
}

#############################################################
# get_userLogConfig -
#    Output:
#      Hash with keys of the format GENERATOR-DOMAIN and
#    values of 'yes' and 'no'
#      get_userLogConfig parses /etc/stats.conf, takes the
#    relavant values from /var/cpanel/cpanel.config and
#    finally parses the user's ~/tmp/stats.conf if the
#    server is configured to allow users to override their
#    stats generators.
#############################################################
sub get_userLogConfig {
    my ( $user, $homedir, $cpuser_ref, $maindomain, $domain_ref ) = @_;
    my @DEFAULT_GENS;
    my @gens = qw(webalizer awstats analog);    # Start with all by default.

    # Load admin supplied gens for user if we have them
    if ( defined( $cpuser_ref->{'STATGENS'} ) ) {
        @gens = split( /,/, $cpuser_ref->{'STATGENS'} );
    }

    # Figure out which gens are skipped globally
    foreach my $gen (qw(WEBALIZER AWSTATS ANALOG)) {
        if ( $main::CPCONF{ 'skip' . lc($gen) } == 1 ) { @gens = grep( !/^${gen}$/i, @gens ); }
    }

    # Load default generators if we have 'em
    if ( defined( $STAT_CONF{'DEFAULTGENS'} ) && $STAT_CONF{'DEFAULTGENS'} ne '' ) {
        @DEFAULT_GENS = split( /,/, $STAT_CONF{'DEFAULTGENS'} );
    }
    else { @DEFAULT_GENS = @gens; }

    my %conf;
    foreach my $gen (@gens) {
        foreach my $domain ( $maindomain, @{$domain_ref} ) {
            my $dom = Cpanel::WildcardDomain::encode_wildcard_domain($domain);
            if ( grep( /^${gen}$/i, @DEFAULT_GENS ) ) {    # if it's a 'default' generator, use it.
                $conf{ uc($gen) . '-' . uc($dom) } = 'yes';
                $conf{ uc($gen) . '-' . uc( 'www.' . $dom ) } = 'yes';
            }
            else {
                $conf{ uc($gen) . '-' . uc($dom) } = 'no';               # otherwise, don't.
                $conf{ uc($gen) . '-' . uc( 'www.' . $dom ) } = 'no';    # otherwise, don't.
            }
        }
    }
    my @users = ( defined $STAT_CONF{'VALIDUSERS'} ) ? split( /,/, $STAT_CONF{'VALIDUSERS'} ) : ();
    if ( defined $STAT_CONF{'ALLOWALL'} && lc( $STAT_CONF{'ALLOWALL'} ) ne 'yes' ) {
        return %conf if ( !grep( /^$user$/i, @users ) );
    }

    my ( $u_conf_hr, $err );
    if ( -e $homedir . '/tmp/stats.conf' ) {
        ( $u_conf_hr, undef, undef, $err ) = Cpanel::Config::LoadConfig::loadConfig( $homedir . '/tmp/stats.conf' );
        warn "loadConfig($homedir/tmp/stats.conf): " . ( $err // '' ) if !$u_conf_hr;
        $u_conf_hr ||= {};

        foreach my $key ( sort keys %$u_conf_hr ) {
            my ( $gen, $dom ) = split( /-/, $key, 2 );
            if ( !grep( /^${gen}$/i, @gens ) ) {
                $u_conf_hr->{$key} = 'no';
            }
        }
        @conf{ keys %$u_conf_hr } = values %$u_conf_hr;
    }
    else {
        main::StatsLog( 0, qq{Can't find } . $homedir . '/tmp/stats.conf ... skipping' );
    }

    return %conf;
}

###############################################################################
#
###############################################################################
sub parsequota {
    my ( $disk, $user ) = @_;

    my $quota_map = Cpanel::SysQuota::fetch_quota_map();

    if ( !ref $quota_map ) {
        main::StatsLog( 0, "Failed to fetch disk usage for $user on $disk" );
        return ( 0, 0 );
    }

    if ( exists $quota_map->{'map'}{$disk}{$user} ) {
        return ( int $quota_map->{'map'}{$disk}{$user}->[1], int $quota_map->{'map'}{$disk}{$user}->[0] );
    }
    else {
        return ( 0, 0 );
    }
}

###############################################################################
#
###############################################################################
sub withinthreshhold {
    my ( $disk, $user, $thresh, $parsed_quota ) = @_;
    if ( !defined $thresh || $thresh eq '' ) { $thresh = 256; }
    my ( $limit, $used );
    if ( ref $parsed_quota && exists $parsed_quota->{'limit'} && exists $parsed_quota->{'used'} ) {
        ( $limit, $used ) = ( $parsed_quota->{'limit'}, $parsed_quota->{'used'} );
    }
    else {
        ( $limit, $used ) = parsequota( $disk, $user );

    }
    return 1 if ( !defined $limit || !defined $used || $limit == 0 );
    return ( ( $limit - $used ) > $thresh );
}

###############################################################################
#
###############################################################################
sub hasexceededquota {
    my ( $disk, $user, $parsed_quota ) = @_;
    my ( $limit, $used );
    if ( ref $parsed_quota && exists $parsed_quota->{'limit'} && exists $parsed_quota->{'used'} ) {
        ( $limit, $used ) = ( $parsed_quota->{'limit'}, $parsed_quota->{'used'} );
    }
    else {
        ( $limit, $used ) = parsequota( $disk, $user );

    }
    return 0 if ( !defined $limit
        || !defined $used
        || $limit == 0
        || $used < $limit );
    return 0;
}

##############################################################################
# get_mountinfo
#   Given a path to search for and type, get_mountinfo returns a string
#   representing the requested device or mountpoint.
#     ie.  get_mountinfo('/home/nirosys'); # returns '/home' if /home is the
#          mountpoint
#          getmountinfo('/home/nirosys','dev'); # returns '/dev/hda2'
##############################################################################
sub get_mountinfo {
    my $path    = shift;
    my $dev     = shift || '';
    my $abspath = Cwd::abs_path($path);
    return if ( !defined $abspath );

    my $mount_ref = _fetch_parsed_mount();

    my @pathelements = split /\//, $abspath;

    if ( !scalar keys %{$mount_ref} ) {
        warn 'Unable to parse mount output.';
        return;
    }

    my $mountpoint;
    foreach my $element ( 0 .. $#pathelements ) {
        my $path = join '/', @pathelements;
        if ( $path eq '' ) { $path = '/' }
        if ( exists $mount_ref->{$path} ) {
            $mountpoint = $path;
            last;
        }
        pop @pathelements;
    }
    if ( !$mountpoint ) {
        warn "Unable to locate appropriate mountpoint for $abspath";
        return;
    }
    return $mount_ref->{$mountpoint} if ( $dev eq 'dev' );
    return $mountpoint;
}

sub _fetch_parsed_mount {
    my $mtab_mtime = ( stat('/etc/mtab') )[9];
    return \%cached_mount if scalar keys %cached_mount && $mtab_mtime == $cached_mount_mtime;
    %cached_mount = ();

    my $mount_bin = Cpanel::Binaries::path('mount');
    return if !-x $mount_bin;

    foreach ( split( /\n/, `$mount_bin` ) ) {
        if ( m{ \A (\S+) \s* on \s* (\S+) }xms && $1 ne $2 ) {    # $1 ne $2 is a check for bind mounts on top of themselves (we should ignore them)
            if ( substr( $2, 0, 1 ) eq '/' ) {
                $cached_mount{$2} = $1;
            }
        }
    }

    $cached_mount_mtime = $mtab_mtime;

    return \%cached_mount;
}

sub nooutputsystembg {
    my (@unsafecmd) = @_;
    my @cmd;
    while ( $unsafecmd[$#unsafecmd] eq '' ) { pop(@unsafecmd); }
    foreach (@unsafecmd) {
        my @cmds = split( / /, $_ );
        foreach (@cmds) { push( @cmd, $_ ); }
    }
    if ( fork() ) {

        #master
    }
    else {
        close(STDOUT);
        close(STDERR);
        close(STDIN);
        open( STDIN,  '<', '/dev/null' );
        open( STDOUT, '>', '/dev/null' );
        open( STDERR, '>', '/dev/null' );
        exec @cmd or exit;
    }
    sleep 5;
}

# NOTE: this method parses the whole file at once.
# If we had bytes files that stretch back more than 1 year, this could cause
# a temporary memory issue.
#   See FogBugz case 24854 for discussion.
sub parsehttpbyteslog {
    my ( $db, $bytes_log, $maxsize, $bbt, $biglock ) = @_;
    die "Failed to acquire a biglock" if !$biglock;

    # $db has been made safe before coming here.

    my $domain = Cpanel::WildcardDomain::decode_wildcard_domain($db);

    my $now = time;
    if ($bytes_log) {

        # The second-order backups should only be created when we were going to
        # do a backup, but one already existed.
        if ( -f "${bytes_log}2" ) {

            # handle second-order backup.
            Cpanel::Bandwidth::BytesLogs::parse( "http/$domain", "${bytes_log}2", $maxsize, $bbt );
            unlink("${bytes_log}2");
        }
        Cpanel::Bandwidth::BytesLogs::parse( "http/$domain", $bytes_log, $maxsize, $bbt );
    }
    unlink($bytes_log);

    return 1;
}

# NOTE: this method parses the whole file at once.
# If we had bytes files that stretch back more than 1 year, this could cause
# a temporary memory issue.
#   See FogBugz case 24854 for discussion.
sub parsebyteslog {
    my ( $db, $type, $bytes_log, $maxsize, $bbt, $biglock ) = @_;
    die "Failed to acquire a biglock" if !$biglock;

    # If necessary, the $db has been made safe before it gets here.

    my $now = time;
    my $bkup;
    if ($bytes_log) {
        $bkup = "$bytes_log.bkup";

        # Process leftover backup file in case we failed.
        if ( -f $bkup ) {
            Cpanel::Bandwidth::BytesLogs::parse( $type, $bkup, $maxsize, $bbt );
            unlink $bkup;
        }

        if ( -f $bytes_log ) {
            rename( $bytes_log, $bkup );
            Cpanel::Bandwidth::BytesLogs::parse( $type, $bkup, $maxsize, $bbt );
        }
    }

    # Only delete once everything is saved.
    unlink $bkup if $bkup;

    return 1;
}

sub parseeximlog {
    my ( $db, $maxsize, $bbt, $biglock ) = @_;
    die "Failed to acquire a biglock" if !$biglock;
    my $now = time;

    my $eximstats_ref = geteximstats( $db, $biglock );
    my $tbytes;
    foreach my $time ( keys %{$eximstats_ref} ) {
        $tbytes = $eximstats_ref->{$time};
        if ( $tbytes < 0 ) { main::StatsLog( 0, "Smtp Bytes overflow $db $_" ); next; }
        next if ( $tbytes > $maxsize );    #corrupt log file line
        unless ($time) {
            main::StatsLog( 1, "0 time value detected for $tbytes bytes in exim log.\n" );
            next;
        }

        # geteximstats returns 5 minute summaries with integer byte counts.
        $bbt->update( 'smtp', $time, $tbytes );
    }

    return 1;
}

# NOTE: this method parses the whole file at once.
# If we had bytes files that stretch back more than 1 year, this could cause
# a temporary memory issue.
#   See FogBugz case 24854 for discussion.
sub parseftpbyteslog {
    my ( $db, $log, $maxsize, $bbt, $biglock ) = @_;
    die "Failed to acquire a biglock" if !$biglock;
    my $now = time;

    if ($log) {
        Cpanel::Bandwidth::BytesLogs::parse_ftplog( 'ftp', $log, $maxsize, $bbt );
    }

    return 1;
}

sub logreset {
    my $log = shift;
    if ( -f $log && unlink $log ) {
        clearoffset($log);
    }
}

#
# Return true if the supplied filename refers to a file that exists and is
# newer than the supplied epoch time.
sub fileisnewerthan {
    my ( $file, $mtime ) = @_;
    my $filemtime = ( stat($file) )[9];
    return 1 if defined $filemtime && ( $filemtime >= $mtime );
    return 0;
}

sub setAccessLogPerms {
    my ( $gid, $maindomain, $domainref ) = @_;
    my @ACCESSLOGS;
    my @LOG_PATH;
    my $filename;
    my $dwaccess_log;
    foreach my $ddomain ( $maindomain, @{$domainref} ) {
        if ( $dwaccess_log = Cpanel::Logs::find_wwwaccesslog($ddomain) ) {
            push( @ACCESSLOGS, $dwaccess_log, $dwaccess_log . '-ssl_log' );
            @LOG_PATH = split( /\//, $dwaccess_log );
            $filename = pop @LOG_PATH;

            push( @ACCESSLOGS, join( '/', @LOG_PATH, 'www.' . $filename . '-ssl_log' ) );
        }
        push( @ACCESSLOGS, Cpanel::Logs::find_ftplog($ddomain) );
    }
    foreach my $access_log (@ACCESSLOGS) {
        if ( $access_log && $access_log ne '' && -f $access_log ) {
            chown 0, $gid, $access_log;
            chmod( oct( $main::CPCONF{'logchmod'} ne '' ? $main::CPCONF{'logchmod'} : '0640' ), $access_log );
        }
    }
}

sub create_lastrun_file {
    my ( $user, $file ) = @_;
    my $fullname = "/var/cpanel/lastrun/$user/$file";

    if ( !-d '/var/cpanel/lastrun' ) {
        unlink '/var/cpanel/lastrun';
        mkdir( '/var/cpanel/lastrun', 0700 );
    }
    if ( !-e "/var/cpanel/lastrun/$user" ) {
        mkdir( "/var/cpanel/lastrun/$user", 0700 );
    }

    Cpanel::FileUtils::TouchFile::touchfile($fullname);
    chmod( oct('0600'), $fullname );

    return 1 if -e $fullname;

    main::StatsLog( 1, "Unable to create $file time-lock file for $user" );
    return;
}

sub checkBwUsageDir {
    if ( !-e '/var/cpanel/bwusagecache' ) {
        mkdir( '/var/cpanel/bwusagecache', 0711 );
    }
}

sub checkBwLimitedDir {
    if ( !-e '/var/cpanel/bwlimited' ) {
        mkdir( '/var/cpanel/bwlimited', 0755 );
    }
}

sub webalizerBrokenCheck {
    my $webalizerdir = shift;

    my $webhistsize = ( stat("$webalizerdir/webalizer.current") )[7];
    if ( -e _ && $webhistsize <= 1 ) {
        main::StatsLog( 1, "Broken $webalizerdir/webalizer.current ($webhistsize) removed!!" );
        unlink("$webalizerdir/webalizer.current");
    }
    return;
}

sub webalizerBin ( $applang = 'english' ) {

    my $ulc = $main::CPCONF{root} // q[/usr/local/cpanel];

    foreach my $lang ( $applang, 'english' ) {
        my $webalizer = "$ulc/3rdparty/webalizer/bin/$lang";
        return $webalizer if -x $webalizer;
        main::StatsLog( 50, "[webalizer] cannot use '$webalizer' for language '$applang'" );
    }
    return;
}

sub _webalizerGo {
    my ( $applang, $outputdir, $access_log, $log_name ) = @_;
    return if ( !-e $access_log || -z _ );

    webalizerBrokenCheck($outputdir);

    # If the dns cache gets too big it will slow down performance
    unlink(qq{$outputdir/dns_cache.db}) if -e qq{$outputdir/dns_cache.db} and ( stat(qq{$outputdir/dns_cache.db}) )[7] > ( 1024 * 1024 * 16 );

    my $bin = webalizerBin($applang);
    return unless defined $bin;

    my @conf_args;
    if ( -e "$outputdir/webalizer.conf" ) {
        @conf_args = ( '-c' => "$outputdir/webalizer.conf" );
    }

    if ( length $bin ) {
        Cpanel::Logd::Runner::run(
            'program' => $bin,
            'args'    => [
                @conf_args,
                '-N' => '10',
                '-D' => "$outputdir/dns_cache.db",
                '-R' => '250',
                '-p',
                '-n' => $log_name,
                '-o' => $outputdir,
                $access_log
            ],
            'logger' => $stats_log_obj
        );
    }
    else {
        main::StatsLog( 5, "[webalizer] The system did not process $log_name because the “webalizer” binary is missing or not executable." );
    }

    return;
}

sub _runStatsProgram {
    my (%OPT) = @_;
    main::StatsLog( 3, '[' . $OPT{'prog'} . '] ' . $OPT{'user'} );

    my $applang = _cached_3rdparty_lang( $OPT{'prog'} );

    foreach my $desc ( @{ $OPT{'logfiledesc'} } ) {
        my $domain      = $desc->{domain};
        my $safe_domain = Cpanel::WildcardDomain::encode_wildcard_domain($domain);
        my $access_log  = $desc->{logfile};
        my $logdir      = $desc->{dir};
        chdir('/');

        if ( !fileisnewerthan( $access_log, $OPT{'lastruntime'} ) ) {
            main::StatsLog( 5, "Skipping $OPT{'prog'} update for $domain. Access_Log is older then last run time!" );
            next;
        }

        my ( $outputdir, $log_name );
        if ( $OPT{'maindomainbase'} && $domain eq $OPT{'maindomain'} && !$logdir ) {
            $log_name  = $OPT{'maindomainname'} || $OPT{'maindomain'};
            $outputdir = $OPT{'homedir'} . '/tmp/' . $OPT{'prog'};
        }
        elsif ( $OPT{'maindomainbase'} ) {
            $log_name  = $domain;
            $outputdir = $OPT{'homedir'} . '/tmp/' . $OPT{'prog'} . $logdir . '/' . $safe_domain;
        }
        else {
            $log_name  = $domain;
            $outputdir = $OPT{'homedir'} . '/tmp/' . $OPT{'prog'} . $logdir;
        }

        # This is a pretty hairy conditional
        if ( lc( ${ $OPT{'rLOG_CONF'} }{ uc( $OPT{'prog'} ) . '-' . uc($domain) } ) eq 'yes' ) {
            if ( !-e $outputdir ) {
                Cpanel::SafeDir::MK::safemkdir( $outputdir, '0700' );
            }

            main::StatsLog( 0, "[dologs] execute: $OPT{'prog'} for user: $OPT{'user'}, log: $access_log." );

            try {
                if ( $OPT{'prog'} eq 'webalizer' ) {
                    _webalizerGo( $applang, $outputdir, $access_log, $log_name );
                }
                elsif ( $OPT{'prog'} eq 'analog' ) {
                    _analogGo( $applang, $outputdir, $access_log, $domain );
                }
                elsif ( $OPT{'prog'} eq 'awstats' ) {
                    if ( $logdir && $logdir =~ m/ssl/ ) { $ENV{'AWSTATS_SSL_DIR'} = 1; }    # AWSTATS_SSL_DIR is used internally by awstats.pl
                    _awstatsGo( $outputdir, $access_log, $domain, $OPT{'maindomain'}, $OPT{'rALLDOMAINS'} );
                    delete $ENV{'AWSTATS_SSL_DIR'};
                }
            }
            catch {
                main::StatsLog( 0, "[dologs] Failed to process stats for $domain." );
            };
        }
    }
    main::StatsLog( 5, qq{[$OPT{'prog'}] completed} );
    return 1;
}

sub _awstatsGo {
    my ( $outputdir, $access_log, $domain, $maindomain, $domainref ) = @_;
    my $plain_access_log = $access_log;
    $plain_access_log =~ s/\.bkup2?$//;
    if ( !buildawconf( $outputdir, $plain_access_log, $domain, $maindomain, $domainref ) ) {
        main::StatsLog( 5, "Failed to buildawconf for $plain_access_log" );
        return;
    }
    if ( -f $access_log && -s _ ) {
        my $safe_domain = Cpanel::WildcardDomain::encode_wildcard_domain($domain);

        local $ENV{'AWSTATS_CONFIG'} = $safe_domain;
        my $bin = "$Cpanel::ConfigFiles::CPANEL_ROOT/3rdparty/bin/awstats.pl";
        if ( -x $bin ) {
            Cpanel::Logd::Runner::run(
                'program' => $bin,
                'args'    => [
                    "-config=$safe_domain",
                    "-LogFile=$access_log",
                    '-update'
                ],
                'logger' => $stats_log_obj
            );
        }
        else {
            main::StatsLog( 5, "[awstats] The system did not process $access_log because the “awstats.pl” script is missing or not executable." );
        }

        delete $ENV{'AWSTATS_CONFIG'};
    }
    else {

        # The upstream logic should not let us get here, but check for it just in case.
        main::StatsLog( 5, "[awstats] Empty log file '$access_log', skipping processing" );
    }

    return 1;
}

sub _analogGo {
    my ( $applang, $outputdir, $access_log, $domain ) = @_;
    return if ( !-e $access_log || -z _ );
    my $outfile = $outputdir . '/' . getmonth() . '.html';
    my $bin     = "$Cpanel::ConfigFiles::CPANEL_ROOT/3rdparty/bin/analog";
    if ( -x $bin ) {
        Cpanel::Logd::Runner::run(
            'program' => $bin,
            'args'    => [
                '+CIMAGEDIR /images/',
                "+CDOMAINSFILE /usr/local/cpanel/3rdparty/share/analog/${applang}dom.tab",
                '+CCHARTDIR ./',
                '+CALLCHART ON',
                "+CLANGFILE /usr/local/cpanel/3rdparty/share/analog/${applang}.lng",
                "+COUTFILE $outfile",
                "+CLOCALCHARTDIR $outputdir/",
                "+CCACHEOUTFILE $outputdir/cache.out",
                "+CCACHEFILE $outputdir/cache",
                '+CVHOST ON', '+COSREP ON', '+CBROWSER ON',
                '+CFULLBROWSER ON',
                '+CREDIRREF ON',
                '+CREFSITE ON', '+CFAILREF ON',
                '+CLogFormat COMBINED',
                "+CHOSTNAME $domain",
                "+CHOSTURL http://$domain/", $access_log
            ],
            'logger' => $stats_log_obj
        );
    }
    else {
        main::StatsLog( 5, "[analog] The system did not process $access_log because the “awstats.pl” script is missing or not executable." );
    }

    unlink("$outputdir/cache");
    rename( "$outputdir/cache.out", "$outputdir/cache" );
    return;
}

sub checkDiskSpaceOk {
    my $user    = shift;
    my $homedir = shift;
    my $dev     = get_mountinfo( $homedir . '/tmp', 'dev' );

    my ( $limit, $used ) = parsequota( $dev, $user );

    main::StatsLog( 0, "Disk Usage for $user on $dev ($used/$limit)" );

    if ( hasexceededquota( $dev, $user, { 'limit' => $limit, 'used' => $used } ) ) {
        main::StatsLog( 0, "!!! Disk Quota Exceeded !!! ${user}'s stats will not be processed until this is resolved." );
        return 0;
    }
    elsif ( !withinthreshhold( $dev, $user, $main::CPCONF{'statthreshhold'}, { 'limit' => $limit, 'used' => $used } ) ) {
        main::StatsLog( 0, "!!! Disk Quota Threshold Met !!! ${user}'s stats will not be processed until this is resolved." );
        return 0;
    }
    return 1;
}

sub loadConfs {
    main::loadcpconfWithDefaults();

    %CACHED_THIRDPARTY_LANG = ();

    my ( $ref, undef, undef, $err ) = Cpanel::Config::LoadConfig::loadConfig( '/etc/stats.conf', \%STAT_CONF );
    warn $err if !$ref;

    main::updateBlackHours( \%STAT_CONF );

    $dcycle  = ( $main::CPCONF{'cycle_hours'} * 3600 );
    $bwcycle = $main::CPCONF{'bwcycle'} * 3600 || 7200;    # default to 2 hours.
    $bwcycle = 86400 if $bwcycle > 86400;                  # limit to one day.

    return;
}

#
# Disconnect the hardlinks from the log files to the user's copy of the log
# files. This allows the
sub tear_down_loglinkage {
    my ( $user, $gid, $logs_ref ) = @_;
    my $changes = 0;

    my $linkdir = apache_paths_facade->dir_domlogs() . "/$user";
    if ( !-e $linkdir ) {
        mkdir( $linkdir, 0750 );
        chown( 0, $gid, $linkdir );
        return;
    }

    foreach my $logdesc ( @{$logs_ref} ) {
        next if $logdesc->{keep};
        my $linkfile = "$linkdir/$logdesc->{filename}";
        next unless -e $linkfile;
        unlink($linkfile);
        ++$changes;
    }

    return $changes;
}

#
# Put the logging hard links back (creating the log files if necessary).
sub restore_loglinkage {
    my ( $user, $uid, $gid, $homedir, $logs_ref ) = @_;

    my $linkdir = apache_paths_facade->dir_domlogs() . "/$user";
    if ( !-e $linkdir ) {
        mkdir( $linkdir, 0750 );
        chown( 0, $gid, $linkdir );
    }

    foreach my $logdesc ( @{$logs_ref} ) {
        my $origfile = $logdesc->{logfile};
        $origfile =~ s/\.bkup$//;
        my $linkfile = "$linkdir/$logdesc->{filename}";

        # Recreate log file if Apache hasn't already.
        if ( !-e $origfile ) {
            open( my $fh, '>>', $origfile ) or next;
            chown( 0, $gid, $fh );
            chmod( 0640, $fh );
            close $fh;
        }
        else {
            chown( 0, $gid, $origfile );
            chmod( 0640, $origfile );
        }

        # restore link
        if ( !-e $linkfile ) {
            link( $origfile, $linkfile );
            next;
        }

        # We'll only get here if the link file currently exists.
        if ( ( stat($origfile) )[1] != ( stat($linkfile) )[1] ) {

            # If we are marked not to delete and the link is bad, correct it.
            main::StatsLog( 0, "$origfile linkage to $linkfile was broken, resetting...." );
            unlink($linkfile);
            link( $origfile, $linkfile );
            main::StatsLog( 0, "Done" );
            next;
        }
    }

    my $has_access_logs_dir = -e $homedir . '/access-logs' ? 1 : 0;
    my $has_logs_symlink    = -l $homedir . '/logs'        ? 1 : 0;
    if ( !$has_access_logs_dir || $has_logs_symlink ) {
        my ( $status, $statusmsg ) = Cpanel::AccessIds::ReducedPrivileges::call_as_user(
            sub {
                if ($has_logs_symlink) {
                    unlink( $homedir . '/logs' );
                    mkdir( $homedir . '/logs', 0700 ) || return ( 0, "Could not create $homedir/logs: $!" );
                }
                if ( !$has_access_logs_dir ) {
                    symlink( apache_paths_facade->dir_domlogs() . "/$user", $homedir . '/access-logs' ) || return ( 0, 'Could not symlink ' . apache_paths_facade->dir_domlogs() . "/$user to $homedir/access-logs" );
                }
                return ( 1, 'OK' );
            },
            $uid,
            $gid
        );
        if ( !$status ) {
            main::StatsLog( 0, "Could not set logs symlink: $statusmsg" );
        }
    }
    return;
}

sub build_complete_domain_arrayref {
    my ( $cpuser, $hr_live_domains ) = @_;
    my @ALL_DOMAINS_AND_DEAD_DOMAINS;
    if ( exists $cpuser->{'DOMAIN'} and length $cpuser->{'DOMAIN'} ) {
        push @ALL_DOMAINS_AND_DEAD_DOMAINS, $cpuser->{'DOMAIN'};
    }
    if ( ref $cpuser->{'DOMAINS'} eq 'ARRAY' ) {
        push @ALL_DOMAINS_AND_DEAD_DOMAINS, @{ $cpuser->{'DOMAINS'} };
    }

    ## note: filters DEADDOMAINS on the list of live domains (domains that have been "reowned")
    if ( ref $cpuser->{'DEADDOMAINS'} eq 'ARRAY' ) {
        my @_deaddomains     = @{ $cpuser->{'DEADDOMAINS'} };
        my @_truedeaddomains = grep { !exists $hr_live_domains->{$_} } @_deaddomains;
        push @ALL_DOMAINS_AND_DEAD_DOMAINS, @_truedeaddomains;
    }
    return \@ALL_DOMAINS_AND_DEAD_DOMAINS;
}

sub _scanlog_loadcpuser {
    my ( $user, $gid ) = @_;
    return unless Cpanel::Config::HasCpUserFile::has_cpuser_file($user);
    my $cpuser = Cpanel::Config::LoadCpUserFile::loadcpuserfile($user);

    # Failed to load the user.
    return if !defined $cpuser || !scalar keys %{$cpuser};

    return $cpuser;
}

# We need to wait for the restart to finish
# so we can put the log files back in place
#
# We cannot use a background restart here
sub _apache_restart {
    local $SIG{CHLD} = '';    # Allow checking return from system.
    return Cpanel::HttpUtils::ApRestart::safeaprestart();
}

sub _cached_3rdparty_lang {
    my $prog       = shift;
    my $locale     = Cpanel::Locale->get_handle();
    my $locale_tag = $locale->get_language_tag();

    return ( $CACHED_THIRDPARTY_LANG{ $locale_tag . '_' . $prog } ||= $locale->cpanel_get_3rdparty_lang($prog) || 'en' );
}

sub _get_all_stats_config {
    return {
        'analog'    => { 'maindomainbase' => 1 },
        'webalizer' => { 'maindomainbase' => 1 },
        'awstats'   => {},
    };
}

1;
