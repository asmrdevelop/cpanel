package Whostmgr::Accounts::Remove;

# cpanel - Whostmgr/Accounts/Remove.pm               Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cpanel license. Unauthorized copying is prohibited

#XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
#
# NOTE XXX IMPORTANT!!
#
# Please do NOT add additional items to this module directly; instead,
# create entries in Whostmgr::Accounts::Remove::Cleanup. That way the removal
# logic will fire for temporary users as well as for “real” users.
#
#XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

use strict;
use warnings;

use AcctLock                         ();
use Cpanel::Chdir                    ();
use Cpanel::AcctUtils::Suspended     ();
use Cpanel::Async::UserLock          ();
use Cpanel::Auth::Digest::DB::Manage ();
use Cpanel::Auth::Shadow             ();
use Cpanel::PwCache::Validate        ();
use Cpanel::BWFiles                  ();
use Cpanel::Backup::Config           ();
use Cpanel::BandwidthDB::Read::Tiny  ();
use Cpanel::BandwidthMgr             ();
use Cpanel::Config::LoadCpConf       ();
use Cpanel::Config::LoadCpUserFile   ();
use Cpanel::Config::HasCpUserFile    ();
use Cpanel::Config::LoadUserDomains  ();
use Cpanel::Config::HasCpUserFile    ();
use Cpanel::Config::userdata::Remove ();
use Cpanel::ConfigFiles              ();
use Cpanel::ConfigFiles::Apache 'apache_paths_facade';       # see POD for import specifics
use Cpanel::Debug                                     ();
use Cpanel::DB::Map::Remove                           ();
use Cpanel::DB::Map::Reader                           ();
use Cpanel::DB::GrantsFile                            ();
use Cpanel::DB::Utils                                 ();
use Cpanel::DIp::Update                               ();
use Cpanel::DomainIp                                  ();
use Cpanel::Domains                                   ();
use Cpanel::Exception                                 ();
use Cpanel::EmailTracker::Purge                       ();
use Cpanel::Filesys::Home                             ();
use Cpanel::Filesys::Virtfs                           ();
use Cpanel::FtpUtils::Server                          ();
use Cpanel::FtpUtils::Passwd                          ();
use Cpanel::Hooks                                     ();
use Cpanel::HttpUtils::ApRestart::BgSafe              ();
use Cpanel::HttpUtils::Config::Apache                 ();
use Cpanel::IP::Remote                                ();
use Cpanel::IPv6::User                                ();
use Cpanel::IpPool                                    ();
use Cpanel::MysqlUtils::Quote                         ();
use Cpanel::MailTools                                 ();
use Cpanel::OS                                        ();
use Cpanel::Path::Safety                              ();
use Cpanel::Passwd::Shell                             ();
use Cpanel::PromiseUtils                              ();
use Cpanel::PwCache                                   ();
use Cpanel::SafeFile                                  ();
use Cpanel::SafeRun::Env                              ();
use Cpanel::SafeRun::Errors                           ();
use Cpanel::SafeRun::Simple                           ();
use Cpanel::ServerTasks                               ();
use Cpanel::Services::Enabled                         ();
use Cpanel::Signal                                    ();
use Cpanel::StringFunc::Count                         ();
use Cpanel::Sys::Kill                                 ();
use Cpanel::SysAccounts                               ();
use Cpanel::SysQuota                                  ();
use Cpanel::UserFiles                                 ();
use Cpanel::WildcardDomain                            ();
use Cpanel::Mysql::Kill                               ();
use Cpanel::PostgresAdmin::Kill                       ();
use Whostmgr::ACLS                                    ();
use Cpanel::FtpUtils::Proftpd::Kill                   ();
use Cpanel::Userdomains                               ();
use Whostmgr::AcctInfo::Owner                         ();
use Whostmgr::Accounts::DB::Remove                    ();
use Whostmgr::Accounts::Remove::Cleanup               ();
use Whostmgr::Accounts::Remove::ResellerWithoutDomain ();
use Whostmgr::Accounts::Email                         ();
use Whostmgr::Dcpumon                                 ();
use Whostmgr::Integration::Purge                      ();
use Whostmgr::Resellers::Check                        ();
use Whostmgr::Resellers::Setup                        ();
use Whostmgr::Templates::Command::Directory           ();
use Whostmgr::UI                                      ();
use Cpanel::Hostname                                  ();
use File::Path                                        ();    ##no critic(PreferredModules) -- Existing usage that predates the PreferredModules check
use Cpanel::Security::Authn::TwoFactorAuth            ();
use Try::Tiny;

use Cpanel::Imports;

use constant _ENOENT => 2;

my $locale;

my %_PRETTY_SQL = qw(
  mysql      MySQL
  postgresql PostgreSQL
);

sub _removevirtfs {
    my ( $user, $uid ) = @_;
    my $output = '';
    return $output unless defined $user && -d '/home/virtfs/' . $user;

    $output .= Whostmgr::UI::setstatus("Removing Virtfs...");
    my ( $remove_status, $remove_message ) = Cpanel::Filesys::Virtfs::remove_user_virtfs( $user, $uid );

    if ( !$remove_status ) {
        $output .= "Removal of virtfs mounts generated a non-fatal error: $remove_message\n";
    }
    else {
        $output .= "Removal of virtfs mounts: $remove_message\n";
    }
    $output .= Whostmgr::UI::setstatusdone();

    return $output;
}

sub _sql_sanity_check {

    my ( $user, $engine, $map_ref ) = @_;

    if ( !Cpanel::Services::Enabled::is_provided($engine) ) {
        my @dbs;
        try {
            @dbs = Cpanel::DB::Map::Reader->new( cpuser => $user, engine => $engine )->get_databases();
        }
        catch {
            die $_ if !try { $_->isa('Cpanel::Exception::Database::CpuserNotInMap') };
        };

        if (@dbs) {
            die Cpanel::Exception->create( "“[_1]” is disabled but the user “[_2]” possesses [quant,_3,database,databases]. You must enable “[_1]” to remove the user “[_2]”.", [ $_PRETTY_SQL{$engine}, $user, scalar @dbs ] ) if scalar @dbs;
        }
    }

    return;
}

sub cleanup_postgres {
    my ($user) = @_;

    # PostgreSQL is disabled and we already sanity check that the user has no DBs in the DB map
    return "" if !Cpanel::Services::Enabled::is_provided("postgresql");

    my $output = Whostmgr::UI::setstatus("Removing PostgreSQL databases and users");

    try {
        Cpanel::PostgresAdmin::Kill::remove_postgres_assets_for_cpuser($user);
        $output .= Whostmgr::UI::setstatusdone();
    }
    catch {
        $output .= Cpanel::Exception::get_string($_);
        $output .= Whostmgr::UI::setstatuserror();
    };

    return $output;
}

sub cleanup_mysql {
    my ( $user, $keep_remote_databases ) = @_;

    # MySQL is disabled and we already sanity check that the user has no DBs in the DB map
    return "" if !Cpanel::Services::Enabled::is_provided("mysql");

    my $output = '';

    if ($keep_remote_databases) {
        $output .= Whostmgr::UI::setstatus("Skipping the removal of remote MySQL databases and users");
        $output .= Whostmgr::UI::setstatusdone();
        return $output;
    }

    $output .= Whostmgr::UI::setstatus("Removing MySQL databases and users");

    $output .= "\nListing MySQL dbs for removal.";

    my @remove_dbs;
    try {
        @remove_dbs = Cpanel::DB::Map::Reader->new( cpuser => $user, engine => 'mysql' )->get_databases();
    }
    catch {
        $output .= _locale()->maketext( "The system failed to list “[_1]”’s databases because of an error: [_2]", $user, Cpanel::Exception::get_string($_) );
    };

    $output .= "\nFetching MySQL DB Owner information.";
    my $mysql_owner = Cpanel::DB::Utils::username_to_dbowner($user);
    $output .= "\n";

    _drop_databases( $user, \$output, \@remove_dbs ) if scalar @remove_dbs;

    $output .= "\n";
    $output .= Whostmgr::UI::setstatusdone();

    $output .= Whostmgr::UI::setstatus("Revoking MySQL Privs.");

    try {
        Cpanel::Mysql::Kill::killmysqluserprivs($user);
        $output .= Whostmgr::UI::setstatusdone();
    }
    catch {
        $output .= Cpanel::Exception::get_string($_);
        $output .= Whostmgr::UI::setstatuserror();
    };

    return $output;
}

sub _drop_databases {
    my ( $user, $output_ref, $remove_dbs_ref ) = @_;
    require Cpanel::MysqlUtils::Connect;
    my $root_dbh = Cpanel::MysqlUtils::Connect::get_dbi_handle();

    my %drop_dbs = map { $_ => 1 } @$remove_dbs_ref;
    foreach my $db ( sort keys %drop_dbs ) {
        $$output_ref .= "Removing MySQL database “$db”…";
        try {
            $root_dbh->do( "DROP DATABASE " . Cpanel::MysqlUtils::Quote::quote_identifier($db) );
        }
        catch {
            $$output_ref .= _locale()->maketext( "The system failed to drop the database “[_1]” for the user “[_2]” because of an error: [_3]", $db, $user, Cpanel::Exception::get_string($_) );
        };
        $$output_ref .= "Done\n";
    }
    return;
}

sub cleanup_ipv6 {
    my ($user) = @_;

    my $output = '';
    $output .= Whostmgr::UI::setstatus("Removing IPv6");
    my ( $ret, $ipv6address ) = Cpanel::IPv6::User::get_user_ipv6_address($user);
    if ($ret) {
        require Cpanel::IPv6::Utils;
        ( $ret, my $range_name ) = Cpanel::IPv6::Utils::get_range_for_user_from_range_config($user);
        if ( $ret && $range_name ne Cpanel::IPv6::Utils::shared_ipv6_key() ) {
            Cpanel::IPv6::Utils::add_ip_to_reclaimed_list( $ipv6address, $range_name );
        }
        ($ret) = Cpanel::IPv6::Utils::remove_users_range($user);
    }
    else {
        # No IPv6, so nothing to remove.
        $ret = 1;
    }
    $output .= "\n";
    $output .= $ret ? Whostmgr::UI::setstatusdone() : Whostmgr::UI::setstatuserror();
    return $output;
}

sub _killacct {    ## no critic(Subroutines::ProhibitExcessComplexity)  -- Refactoring this function is a project, not a bug fix
    my %OPTS = @_;
    my $output;

    #Black-hole this so we only get one clearstatus()
    my $_clearstatus = \&Whostmgr::UI::clearstatus;
    no warnings 'redefine';
    local *Whostmgr::UI::clearstatus = sub { };

    my $validate_failure;
    my ( $user, $uid, $gid, $userhomedir, $cpuserconf_ref ) = try {
        _validate_killacct(%OPTS);
    }
    catch { $validate_failure = $_ };
    return 0, $validate_failure if $validate_failure;

    my $now = time();

    my $killdns = $OPTS{'killdns'};
    $killdns =~ s/[\s\n]//g;

    # currently only for MySQL/MariaDB
    my $keep_remote_databases = $OPTS{'keep_remote_databases'} ? 1 : 0;

    umask(0022);    #reset umask for update

    # Ensure we do not try chdir back to a directory we cannot enter
    # if we drop privs later
    my $chdir = Cpanel::Chdir->new('/');

    local $SIG{'PIPE'} = 'IGNORE';
    local $SIG{'HUP'}  = 'IGNORE';

    local $| = 1;

    my $current_account_count = Cpanel::Config::LoadUserDomains::counttrueuserdomains();

    $output .= Whostmgr::UI::setstatus("Running pre removal script (/usr/local/cpanel/scripts/prekillacct)");
    my $pre_removal_failure;
    $output .= try { _run_pre_removal_script(%OPTS) }
    catch { $pre_removal_failure = $_ };
    return 0, $pre_removal_failure if $pre_removal_failure;
    $output .= Whostmgr::UI::setstatusdone();

    my $cpconf_ref = Cpanel::Config::LoadCpConf::loadcpconf();
    my $host       = Cpanel::Hostname::gethostname();

    $output .= Whostmgr::UI::setstatus("Collecting Domain Name and IP");

    my @PDS       = ref $cpuserconf_ref->{'DOMAINS'} ? @{ $cpuserconf_ref->{'DOMAINS'} } : ();
    my $owner     = $cpuserconf_ref->{'OWNER'};
    my $domain    = $cpuserconf_ref->{'DOMAIN'};
    my $domain_ip = $cpuserconf_ref->{'IP'} || Cpanel::DomainIp::getdomainip($domain);

    my @all_user_domains = ( $domain, @PDS );

    my @_raw_deaddomains = ref $cpuserconf_ref->{'DEADDOMAINS'} ? @{ $cpuserconf_ref->{'DEADDOMAINS'} } : ();
    ## filters a user's dead domains from the list of live domains
    my @true_deaddomains = Cpanel::Domains::get_true_user_deaddomains( \@_raw_deaddomains );

    $output .= "User: $user\n";
    $output .= "Domain: $domain\n";

    if ( $domain eq '' ) { return ( 0, 'Error: invalid domain' ); }

    # Hold this throughout the account-removal operation:
    my $exists_lock = Cpanel::PromiseUtils::wait_anyevent(
        Cpanel::Async::UserLock::create_exclusive($user),
    )->get();

    # Ensure we remove
    require Cpanel::PHPFPM;    # TODO: TaskQueue this
    Cpanel::PHPFPM::_killacct($user);

    local $SIG{'INT'} = 'IGNORE';    # prevent killing here

    $output .= Whostmgr::UI::setstatusdone();

    # Case 26718 : change shell to a no login shell so we can clean up virtfs mounts for jailshell without having to worry about them logging back in at just the wrong time
    $output .= Whostmgr::UI::setstatus('Locking account and setting shell to nologin');
    AcctLock::acctlock();

    #
    # DO NOT USE Whostmgr::Accounts::Shell::set_shell here as it will
    # trigger an apache vhost rebuild for the vhost if jailed apache is enabled
    # Whostmgr::Accounts::Shell::set_shell( $user, '/sbin/nologin' );
    #
    # case 53678: Also lock the password so they cannot login during the process and prevent the userdel
    my ( $status, $statusmsg ) = Cpanel::Auth::Shadow::update_shadow_without_acctlock( $user, '!!' );
    $output .= $statusmsg . "\n" if !$status;

    try {
        Cpanel::Passwd::Shell::update_shell_without_acctlock( 'user' => $user, 'shell' => '/sbin/nologin' );
    }
    catch {
        $output .= Cpanel::Exception::get_string($_) . "\n";
    };
    #
    AcctLock::unacctlock();
    $output .= Whostmgr::UI::setstatusdone();

    $output .= Whostmgr::UI::setstatus('Killing all processes owned by user');

    # this returns 0 so do not save the output as it looks ugly
    Cpanel::Sys::Kill::kill_pids_owned_by( $user, 'KILL' );
    $output .= Whostmgr::UI::setstatusdone();

    Cpanel::ServerTasks::schedule_task( ['cPanelFPMTasks'], 5, 'cpanelfpm_remove_user ' . $user );

    # Remove from the trusted user list if present
    Whostmgr::Dcpumon::remove_trusted_user($user);

    my %server_tasks_modules;
    my @queue_tasks;
    if ( Cpanel::Services::Enabled::is_enabled('cpanel_php_fpm') ) {

        # Taskqueue processes tasks in the order they are scheduled.  To ensure
        # the restart happens after the add we schedule it 15s later which
        # is the maximum time we would ever expect the add operation to take
        #
        # TODO: in the future it would be nice to have a way to do a "promise" chain
        # with taskqueue so we can tell it add the user and than do the restart
        # after
        Cpanel::ServerTasks::schedule_task( ['CpServicesTasks'], 20, "restartsrv cpanel_php_fpm" );
    }

    $output .= Whostmgr::UI::setstatus("Removing Suspended Info...");
    if ( Cpanel::AcctUtils::Suspended::is_suspended($user) ) {
        unlink map { "$_/$user" } grep { -e "$_/$user" } (
            '/var/cpanel/suspended',
            '/var/cpanel/suspendinfo',
            Cpanel::OS::user_crontab_dir() . '.suspended'
        );
        $output .= Cpanel::SafeRun::Simple::saferun(
            '/usr/local/cpanel/scripts/generate_account_suspension_include',
            '--update',
        );
    }
    $output .= Whostmgr::UI::setstatusdone();

    ## case 9010: remove bandwidth files for domains/deaddomains
    $output .= Whostmgr::UI::setstatus("Removing Bandwidth Files");
    _remove_bandwidth_files( $user, $domain, \@PDS, \@true_deaddomains );
    $output .= Whostmgr::UI::setstatusdone();

    $output .= Whostmgr::UI::setstatus("Removing Email Sending Limits Cache");
    unlink( map { '/var/cpanel/email_send_limits/cache/' . $_ } (@all_user_domains) );
    my $tomorrow = $now + 86400;
    foreach my $purge_domain (@all_user_domains) {
        Cpanel::EmailTracker::Purge::purge_old_tracker_files_by_domain( $purge_domain, $tomorrow );
        rmdir( '/var/cpanel/email_send_limits/track/' . $purge_domain );    #ok if it doesn't exist
    }
    $output .= Whostmgr::UI::setstatusdone();

    $output .= Whostmgr::UI::setstatus("Removing Crontab");
    unlink( Cpanel::OS::user_crontab_dir() . $user );
    $output .= Whostmgr::UI::setstatusdone();

    cleanup_ipv6($user);

    #----------------------------------------------------------------------

    #TODO: Move more things in this module into Whostmgr::Accounts::Remove::Cleanup
    #so that eventually both permanent and temporary users share the same
    #cleanup logic.
    my $cleanup = Whostmgr::Accounts::Remove::Cleanup->new(
        username    => $user,
        cpuser_data => $cpuserconf_ref,
        todo_before => sub { $output .= Whostmgr::UI::setstatus(shift); },
        todo_after  => sub { $output .= Whostmgr::UI::setstatusdone(); },
        on_error    => sub {
            $output .= Cpanel::Exception::get_string(shift) . "\n";
            $output .= Whostmgr::UI::setstatuserror();
        },
    );
    $cleanup->run();

    # Should be run after cleanup to properly remove cruft of resellers.
    if ( Whostmgr::Resellers::Check::is_reseller($user) ) {
        Whostmgr::Resellers::Setup::_unsetupreseller($user);
    }

    # Remove vhosts before removing dirs to avoid
    # a problem with apache restarting in the middle
    #
    # However we want to remove them AFTER we do
    # Whostmgr::Accounts::Remove::Cleanup to ensure it happens after
    # ATLS and Domain TLS are removed.
    #----------------------------------------------------------------------
    $output .= Whostmgr::UI::setstatus("Removing HTTP virtual hosts");
    $output .= _remove_httpd_vhosts( $user, @all_user_domains );
    $output .= Whostmgr::UI::setstatusdone();

    $output .= Whostmgr::UI::setstatus("Removing FTP virtual hosts");
    Cpanel::FtpUtils::Proftpd::Kill::remove_servername_from_conf($domain);
    $output .= Whostmgr::UI::setstatusdone();

    $output .= Whostmgr::UI::setstatusdone();

    # case CPANEL-17124 : remove userdata before we delete the virtual hosts
    # from httpd.conf
    #  *** We must remove the userdata BEFORE removing the httpd.conf data
    #  *** to ensure that a background process does not re-add the vhosts
    #  *** back between when we remove them below and the user is deleted as this
    #  *** will result in apache failing to startup with
    #  *** "httpd: bad user name f03efrhxxni"
    # Clear public_html convenience symlinks; MUST be done before clearing userconfig
    $output .= Whostmgr::UI::setstatus("Removing user's web content directory symlinks");
    _remove_public_html_symlinks( $userhomedir, $user );
    _remove_user_webdirs($user);
    $output .= Whostmgr::UI::setstatusdone();

    $output .= Whostmgr::UI::setstatus("Removing Two-Factor Authentication entries....");
    try {
        my $tfa = Cpanel::Security::Authn::TwoFactorAuth->new( { 'user' => $user } );
        $tfa->remove_tfa_userdata();
    }
    catch {
        $output .= Cpanel::Exception::get_string($_) . "\n";
    };
    $output .= Whostmgr::UI::setstatusdone();

    $output .= cleanup_mysql( $user, $keep_remote_databases );
    $output .= cleanup_postgres( $user, $uid );

    $server_tasks_modules{'MysqlTasks'} = 1;
    push @queue_tasks, "dbindex $user";

    try {
        Cpanel::DB::GrantsFile::delete_for_cpuser($user);
    }
    catch {
        $output .= Cpanel::Exception::get_string($_) . "\n";
    };

    $output .= Whostmgr::UI::setstatus("Removing WHM API Token entries....");
    try {
        require Cpanel::Security::Authn::APITokens::Write::whostmgr;
        Cpanel::Security::Authn::APITokens::Write::whostmgr->remove_user($user);
    }
    catch {
        $output .= Cpanel::Exception::get_string($_) . "\n";
    };
    $output .= Whostmgr::UI::setstatusdone();

    $output .= Whostmgr::UI::setstatus("Removing cPanel API Token entries....");
    try {
        require Cpanel::Security::Authn::APITokens::Write::cpanel;
        Cpanel::Security::Authn::APITokens::Write::cpanel->remove_user($user);
    }
    catch {
        $output .= Cpanel::Exception::get_string($_) . "\n";
    };

    $output .= Whostmgr::UI::setstatusdone();

    # remove virtfs user's directory before attempting to delete the user
    # or we may get -EBUSY
    $output .= _removevirtfs( $user, $uid );

    $output .= Whostmgr::UI::setstatus("Removing User & Group....");
    try {
        Cpanel::SysAccounts::remove_system_user(
            $user,
            $Cpanel::SysAccounts::UNLOCK,
        ) or die;
        $output .= 'Success';
    }
    catch {
        $output .= 'Failure' . ( $_ ? ': ' . Cpanel::Exception::get_string($_) : '' );
    };
    $output .= Whostmgr::UI::setstatusdone();
    $output .= "\n";

    $userhomedir =~ s{//+}{/}g;
    $userhomedir =~ s/\/$//g;
    my @BASEHOME           = split /\//, $userhomedir;
    my $perl_installer_dir = join '/' => (
        @BASEHOME[ 0 .. $#BASEHOME - 1 ],
        '.perlinstaller',
        $uid,
    );
    for ( grep { -d and $uid and Cpanel::StringFunc::Count::countchar( $_, '/' ) >= 2 and (stat)[4] == $uid } ( $userhomedir, $perl_installer_dir ) ) {
        $output .= Cpanel::SafeRun::Errors::saferunallerrors( 'rm', '-rf', '--', "$_/" );
    }

    #Don't alias in this loop.
    for my $homedirlink_path_alias ( grep { -l } @{ $cpuserconf_ref->{HOMEDIRLINKS} } ) {

        my $homedirlink_path = $homedirlink_path_alias;
        $homedirlink_path =~ s{//+}{/}g;

        #prevent unlinking root files
        if ( Cpanel::StringFunc::Count::countchar( $homedirlink_path, '/' ) >= 2 ) {
            unlink($homedirlink_path) or warn "Failed to unlink symlink $homedirlink_path: $!";
        }
    }

    # Valiases already removed in Cleanup.pm

    $output .= Whostmgr::UI::setstatus("Updating Databases");
    Whostmgr::Accounts::DB::Remove::remove_user_and_domains( $user, [ @all_user_domains, @true_deaddomains ] );
    $output .= Whostmgr::UI::setstatusdone();

    $output .= Whostmgr::UI::setstatus("Removing bandwidth limits");
    Cpanel::BandwidthMgr::disablebwlimit( $user, $domain, undef, undef, undef, [ @PDS, @true_deaddomains ] );
    $output .= Whostmgr::UI::setstatusdone();

    $output .= Whostmgr::UI::setstatus("Removing Counter Data");
    $output .= Whostmgr::UI::setstatusdone();

    $output .= Whostmgr::UI::setstatus("Removing user's cPanel Databases & Updating");
    _remove_cpanel_databases_and_cache($user);

    Cpanel::Domains::add_deleted_domains( $user, $owner, $domain, \@PDS );

    File::Path::rmtree( [ "/var/cpanel/lastrun/$user", "$Cpanel::ConfigFiles::USER_NOTIFICATIONS_DIR/$user" ] );

    Cpanel::FtpUtils::Passwd::remove( $user, $domain_ip );

    Cpanel::Userdomains::updateuserdomains();
    require Cpanel::Config::userdata::UpdateCache;
    $output .= Cpanel::Config::userdata::UpdateCache::update($user)                 || '';
    $output .= Cpanel::DIp::Update::update_dedicated_ips_and_dependencies_or_warn() || '';
    $output .= Whostmgr::UI::setstatusdone();

    $output .= Whostmgr::UI::setstatus("Adding IP back to the IP address pool");
    my $freeips = Cpanel::IpPool::rebuild();
    $output .= "System has $freeips free ip" . ( $freeips == 1 ? '' : 's' ) . ".\n";
    $output .= Whostmgr::UI::setstatusdone();

    # We must must remove the DB Map AFTER updateuserdomains in order to avoid a race condition
    # where it could come back
    Cpanel::DB::Map::Remove::remove_cpuser($user);

    $output .= Whostmgr::UI::setstatus("Reloading Services");

    if ( Cpanel::FtpUtils::Server::using_proftpd() ) {
        Cpanel::Signal::send_hup_proftpd();
    }

    Cpanel::HttpUtils::ApRestart::BgSafe::restart();
    $output .= Whostmgr::UI::setstatusdone();

    ### SSL resources were already removed when vhosts were purged.

    $output .= Whostmgr::UI::setstatus("Sending Contacts");
    _send_contacts( $owner, $user, $domain, $host );
    $output .= Whostmgr::UI::setstatusdone();

    $output .= Whostmgr::UI::setstatus("Updating internal databases");

    my $acctlog = Cpanel::SafeFile::safeopen( \*ACCTLOG, ">>", "/var/cpanel/accounting.log" );
    if ( !$acctlog ) {
        Cpanel::Debug::log_warn("Could not write to /var/cpanel/accounting.log");
        return;
    }
    chmod 0600, '/var/cpanel/accounting.log';
    my $localtime = localtime($now);
    print ACCTLOG "$localtime:REMOVE:$ENV{'REMOTE_USER'}:$ENV{'USER'}:$domain:$user\n";
    Cpanel::SafeFile::safeclose( \*ACCTLOG, $acctlog );

    Cpanel::ServerTasks::schedule_task( ['CpDBTasks'], 10, "ftpupdate" );

    $output .= Whostmgr::UI::setstatusdone();

    # Do dns removal at the very end since if the account
    # was just created it could be setting up DKIM or SPF.
    #
    # We put the removeal into the task queue so it that if DKIM or SPF
    # setup it taking a while in the queue this will always be behind it
    # so the zone does not unexpectedly get recreated.
    #
    if ($killdns) {
        $output .= Whostmgr::UI::setstatus("Removing DNS Entries");
        $server_tasks_modules{'DNSTasks'} = 1;
        $output .= _remove_dns_entries( \@all_user_domains, \@queue_tasks );
        $output .= Whostmgr::UI::setstatusdone();
    }

    Cpanel::ServerTasks::queue_task( [ keys %server_tasks_modules ], @queue_tasks );

    Cpanel::Auth::Digest::DB::Manage::remove_entry($user);

    # No longer needed.  This was a workaround for a bug in grpck
    # system("killall -9 yes 2>/dev/null");
    $output .= Whostmgr::UI::setstatus("Running post removal scripts (/usr/local/cpanel/scripts/legacypostkillacct, /usr/local/cpanel/scripts/postkillacct)");
    $output .= _run_post_removal_scripts(%OPTS);
    $output .= Whostmgr::UI::setstatusdone();

    # Check for leftover files must be done after removevirtfs
    _check_for_leftover_files_and_notify_admin( 'output_ref' => \$output, 'user' => $user, 'uid' => $uid, 'gid' => $gid, 'owner' => $owner );

    $output .= Whostmgr::UI::setstatus("Account Removal Complete!!!");
    $output .= "\n$user account removed";

    # might affect multiuser_required and minimum_accounts_needed evaluations in dynamicui.conf
    if ( $current_account_count == 1 || $current_account_count == 2 ) {
        Whostmgr::Templates::Command::Directory::clear_cache_dir();
    }

    $output .= Whostmgr::UI::setstatusdone();
    $output .= $_clearstatus->() || '';

    # let's validate that some directories were actually removed
    # if not, we should not consider this a success

    require Cpanel::AcctUtils::Account;

    my $existing_parts = Cpanel::AcctUtils::Account::get_existing_account_parts($user);

    if ( scalar @{$existing_parts} ) {
        return ( 0, "$user account was not completely removed (" . join( ", ", @{$existing_parts} ) . ")", $output );
    }

    return ( 1, "$user account removed", $output );
}

sub _validate_killacct {
    my (%OPTS) = @_;

    my $if_child = $OPTS{'if_child'} //= q<>;

    die 'Data cannot contain whitespace or NUL'
      if grep { /[\s\0]/ } ( keys %OPTS, values %OPTS );

    my $user = $OPTS{user} || $OPTS{username};
    $user =~ tr{/ \n\r\t\f}{}d;
    die 'Removing an account requires a username' if not $user;

    my ( $uid, $gid, $userhomedir ) = ( Cpanel::PwCache::getpwnam($user) )[ 2, 3, 7 ];
    die "Warning: user $user does not exist on this system!"
      if not $uid or not $gid;
    die "Warning: user $user does not have a valid home directory!"
      if not $userhomedir;
    die "Error: Unable to find data for $user"
      if not Cpanel::Config::HasCpUserFile::has_cpuser_file($user);

    my $cpuserconf_ref = Cpanel::Config::LoadCpUserFile::loadcpuserfile($user);
    die "Error: Unable to load cPanel data for $user"
      if not keys %{$cpuserconf_ref};

    if ( length $if_child && $if_child ne 'remove' ) {
        die "Invalid “if_child” ($if_child)!";
    }

    if ( $cpuserconf_ref->child_workloads() && $if_child ne 'remove' ) {
        die "To remove this account, do so on its parent node.\n";
    }

    _sql_sanity_check( $user, "mysql" );
    _sql_sanity_check( $user, "postgresql" );

    return $user, $uid, $gid, $userhomedir, $cpuserconf_ref;
}

sub _run_pre_removal_script {
    my (%OPTS) = @_;
    my $output = '';

    if ( -x '/usr/local/cpanel/scripts/prekillacct' ) {
        my $outref = Cpanel::SafeRun::Env::saferun_r_cleanenv( '/usr/local/cpanel/scripts/prekillacct', %OPTS );
        if ( ref $outref eq 'SCALAR' ) { $output .= ${$outref} }
    }
    my ( $pre_hook_result, $hook_msgs ) = Cpanel::Hooks::hook(
        {
            category => 'Whostmgr',
            event    => 'Accounts::Remove',
            stage    => 'pre',
            blocking => 1,
        },
        \%OPTS,
    );
    my $hooks_msg = @{$hook_msgs} ? join "\n", @{$hook_msgs} : '';
    die "Hook denied execution of killacct: $hooks_msg"
      if not $pre_hook_result;
    $output .= $hooks_msg;

    return $output;
}

sub _remove_user_webdirs {
    my $user = shift;

    # glob already required for templates
    my @soft_unlinks = map { glob apache_paths_facade->dir_conf_userdata() . $_ } (
        "/*.owner-$user",
        "/std/*.owner-$user",
        "/ssl/*.owner-$user",
        "/std/2/*.owner-$user",
        "/std/1/*.owner-$user",
    );
    push @soft_unlinks, "/var/spool/mail/$user";

    # Clear userconfig
    my @unlinks;

    Whostmgr::Integration::Purge::purge_user($user);

    push @unlinks,
      map  { "$_/$user" }
      grep { $_ and $user and not -l "$_/$user" and -d _ }
      map  { "/var/cpanel/$_" } qw(datastore);

    for my $path (@soft_unlinks) {
        unlink $path or do {
            warn "unlink($path): $!" if $! != _ENOENT();
        };
    }

    File::Path::rmtree( \@unlinks ) if @unlinks;

    Cpanel::Config::userdata::Remove::remove_user($user);
    return;
}

sub _remove_httpd_vhosts {
    my ( $user, @all_user_domains ) = @_;
    my $output = '';

    # Removing vhosts from httpd.conf
    my $httpd_failure;
    my $httpd_conf_obj = try { Cpanel::HttpUtils::Config::Apache->new() }
    catch { $httpd_failure = $_ };
    return "Failed to lock httpd.conf and associated files: $httpd_failure\n"
      if $httpd_failure;

    my ( @std_removed, @ssl_removed, $result, $removed_ar );
    for my $domain_to_purge (@all_user_domains) {

        # For non-SSL domains
        ( $result, $removed_ar ) = $httpd_conf_obj->remove_vhosts_by_name($domain_to_purge);
        if ($result) { push @std_removed, @$removed_ar }
        else {
            $output .= "Failed to remove non-SSL virtual host for domain “$domain_to_purge”\n";
        }

        # For SSL domains
        ( $result, $removed_ar ) = $httpd_conf_obj->remove_vhosts_by_name( $domain_to_purge, 'ssl' );
        if ($result) { push @ssl_removed, @$removed_ar }
        else {
            $output .= "Failed to remove SSL virtual host for domain “$domain_to_purge”\n";
        }
    }

    ( $result, $removed_ar ) = $httpd_conf_obj->remove_vhosts_by_user($user);    ## This always does ssl and non-ssl
    if ($result) { push @std_removed, @$removed_ar }
    else {
        $output .= "Failed to remove non-SSL virtual host(s) served from ${user}’s home directory\n";
    }

    if ($result) {

        # TODO: make this method public and add a test
        #
        # FIXME: ssl resources already cleaned up
        # so don't do it again.
        $httpd_conf_obj->{'_domains_with_ssl_resources_to_cleanup'} = [];

        if ( @std_removed || @ssl_removed ) {
            my ( $httpd_conf_save_ok, $httpd_conf_msg ) = $httpd_conf_obj->save();
            if ( !$httpd_conf_save_ok ) {
                $output .= <<"END_OUTPUT";
Failed to save changes to the Apache configuration file: $httpd_conf_msg
NOTE: The following domains’ SSL data may have been removed, however: @{[ join ' ', map { $_->{servername} } @ssl_removed ]}
END_OUTPUT
            }
        }

        my ( $httpd_conf_close_ok, $httpd_conf_close_msg ) = $httpd_conf_obj->close();
        if ( !$httpd_conf_close_ok ) {
            $output .= <<"END_OUTPUT";
Failed to unlock the Apache configuration file: $httpd_conf_close_msg
NOTE: The following domains’ SSL data may have been removed, however: @{[ join ' ', map { $_->{servername} } @ssl_removed ]}
END_OUTPUT
        }
        else {
            $output .= <<"END_OUTPUT";
Removed the following non-SSL virtual hosts: @{[ join ' ', map { $_->{servername} } @std_removed ]}
Removed the following SSL virtual hosts: @{[ join ' ', map { $_->{servername} } @ssl_removed ]}
END_OUTPUT
        }
    }
    else {
        $output .= "Failed to remove SSL virtual host(s) served from ${user}’s home directory\n";
    }

    return $output;
}

sub _remove_dns_entries {
    my ( $all_user_domains_ar, $queue_tasks_ar ) = @_;

    my $zonedir        = Cpanel::OS::dns_named_basedir();
    my @all_user_zones = sort grep { -e "$zonedir/$_.db" } @$all_user_domains_ar;

    if ( scalar @all_user_zones ) {
        push @$queue_tasks_ar, join( ' ', 'remove_zones', @all_user_zones );
    }

    return 'Zones removed: ' . ( scalar @all_user_zones ) . "\n";
}

sub _remove_mail_service_configs {
    my ( $user, $domain, @PDS ) = @_;

    my @CONFIG_DIRS = (
        $Cpanel::ConfigFiles::VFILTERS_DIR,
        $Cpanel::ConfigFiles::VALIASES_DIR,
        $Cpanel::ConfigFiles::VDOMAINALIASES_DIR,
    );
    for my $domain_name ( @PDS, $domain ) {
        unlink map { "$_/$domain_name" } @CONFIG_DIRS;
        Cpanel::MailTools::remove_vmail_files($domain_name);
    }

    Whostmgr::Accounts::Email::update_outgoing_mail_suspended_users_db(
        user => $user, suspended => 0,
    );
    Whostmgr::Accounts::Email::update_outgoing_mail_hold_users_db(
        user => $user, hold => 0,
    );

    return;
}

sub _send_contacts {
    my ( $owner, $user, $domain, $host ) = @_;
    require Cpanel::Notify::Deferred;

    my %notify_opts = (
        account_owner     => $owner,
        user              => $user,
        user_domain       => $domain,
        host              => $host,
        env_remote_user   => $ENV{REMOTE_USER},
        env_user          => $ENV{USER},
        origin            => 'WHM',
        source_ip_address => Cpanel::IP::Remote::get_current_remote_ip(),
    );

    Cpanel::Notify::Deferred::notify_without_triggering_subqueue(
        class            => 'killacct::Notify',
        application      => 'killacct::Notify',
        constructor_args => [%notify_opts]
    );
    if ( !Whostmgr::ACLS::hasroot() ) {
        ;
        Cpanel::Notify::Deferred::notify_without_triggering_subqueue(
            class            => 'killacct::Notify',
            application      => 'killacct::Notify',
            constructor_args => [
                %notify_opts,
                username => $ENV{REMOTE_USER},
                to       => $ENV{REMOTE_USER},
            ],
        );
    }

    Cpanel::Notify::Deferred::process_notify_subqueue();

    return;
}

sub _run_post_removal_scripts {
    my (%OPTS) = @_;
    my $output = '';

    if ( -x '/usr/local/cpanel/scripts/postkillacct' ) {
        my $outref = Cpanel::SafeRun::Env::saferun_r_cleanenv(
            '/usr/local/cpanel/scripts/postkillacct', %OPTS,
        );
        if ( ref $outref eq 'SCALAR' ) { $output .= ${$outref} }
    }
    if ( -x '/usr/local/cpanel/scripts/legacypostkillacct' ) {
        my $outref = Cpanel::SafeRun::Env::saferun_r_cleanenv(
            '/usr/local/cpanel/scripts/legacypostkillacct',
            @OPTS{qw(user killdns)},
        );
        if ( ref $outref eq 'SCALAR' ) { $output .= ${outref} }
    }
    Cpanel::Hooks::hook(
        {
            category => 'Whostmgr',
            event    => 'Accounts::Remove',
            stage    => 'post',
        },
        \%OPTS,
    );

    return $output;
}

sub remove_account_or_die {
    my %OPTS = @_;
    my ( $status, $msg ) = _removeaccount(%OPTS);
    die $msg if !$status;
    return;
}

sub _removeaccount {
    my %OPTS    = @_;
    my $user    = $OPTS{'user'} || $OPTS{'username'};
    my $killdns = $OPTS{'keepdns'} ? 0 : 1;

    # currently only for MySQL/MariaDB
    my $keep_remote_databases = $OPTS{'keep_remote_databases'} ? 1 : 0;

    if ( !length $user ) {
        return ( 0, 'No user name supplied: "user" is a required argument.' );
    }
    elsif ( $ENV{'REMOTE_USER'} && $user eq $ENV{'REMOTE_USER'} ) {
        return ( 0, "You cannot remove yourself!" );
    }
    elsif ( !( Cpanel::PwCache::getpwnam($user) )[0] ) {
        return ( 0, "System user $user does not exist!" );
    }
    elsif ( $user eq 'virtfs' && !$OPTS{'force'} ) {
        return ( 0, 'Removal of the virtfs user may potentially damage your system.' );
    }
    elsif ($keep_remote_databases) {
        require Cpanel::MysqlUtils::MyCnf::Basic;

        if ( !Cpanel::MysqlUtils::MyCnf::Basic::is_remote_mysql() ) {
            return ( 0, 'MySQL/MariaDB is not configured for remote operation..' );
        }
    }

    if ( Whostmgr::ACLS::hasroot() || Whostmgr::AcctInfo::Owner::checkowner( $ENV{'REMOTE_USER'}, $user ) ) {
        if ( Whostmgr::Accounts::Remove::ResellerWithoutDomain::is_reseller_without_domain( username => $user ) ) {
            return Whostmgr::Accounts::Remove::ResellerWithoutDomain::remove( username => $user );
        }

        return _killacct(
            'user'                  => $user,
            'killdns'               => $killdns,
            'keep_remote_databases' => $keep_remote_databases,
            %OPTS{'if_child'},
        );
    }
    else {
        return ( 0, "You do not have permission to remove that account ($user)!" );
    }
}

sub _remove_bandwidth_files {
    my ( $user, $domain, $ar_PDS, $ar_true_deaddomains ) = @_;

    unlink grep { -e $_ } Cpanel::BWFiles::all_new_and_old_bandwidth_related_files($user);

    for my $dnsdomain ( $domain, @$ar_PDS, @$ar_true_deaddomains ) {
        next if ( $dnsdomain =~ /^\./ );
        unlink grep { -e $_ } Cpanel::BWFiles::all_new_and_old_bandwidth_related_files( Cpanel::WildcardDomain::encode_wildcard_domain($dnsdomain) );

        # The non-safe versions should never occur, but if they do, delete them.
        if ( $dnsdomain =~ /^\*/ ) {
            unlink grep { -e $_ } Cpanel::BWFiles::all_new_and_old_bandwidth_related_files($dnsdomain);
        }
    }

    if ( Cpanel::BandwidthDB::Read::Tiny::user_has_database($user) ) {
        require Cpanel::BandwidthDB::Remove;

        Cpanel::BandwidthDB::Remove::remove_database_for_user($user);
        Cpanel::BandwidthDB::Remove::remove_corrupted_database_for_user($user);
    }

    try {
        require Cpanel::BandwidthDB::RootCache;

        Cpanel::BandwidthDB::RootCache->new()->purge_user($user);
    }
    catch {
        warn $_ if !try { $_->isa('Cpanel::Exception::Database::DatabaseCreationInProgress') };

        #The next round of log processing will handle this.
    };

    require Cpanel::BandwidthDB::UserCache;

    Cpanel::BandwidthDB::UserCache::remove($user);

    return;
}

sub _remove_cpanel_databases_and_cache {
    my ($user) = @_;

    # Remove cache first due to race condition while testing
    unlink( "/var/cpanel/users.cache/$user", "/var/cpanel/users/$user" );
    Cpanel::PwCache::Validate::invalidate( 'user' => $user );
    return;
}

#
# Handle removal of the per-user public_html symlink paths stored in the
# /var/cpanel/userconfig/$user/public_html_symlinks file.
#
# Historically, these symlinks have been created against the /home/virtual
# folder hierarchy, a concession made for the sake of allowing applications
# imported from EnXim machines to continue to operate without issue.  As the
# need arises, this method will be refactored, modified, or deprecated to
# handle changing requirements, and more such directories may be factored
# in.
#
sub _remove_public_html_symlinks {
    my ( $home, $user ) = @_;
    my $public_html_symlinks = Cpanel::UserFiles::public_html_symlinks_file($user);

    open my $fh, '<', $public_html_symlinks or do {
        warn "open($public_html_symlinks): $!" if $! != _ENOENT();
        return;
    };

    while ( my $public_html_symlink = readline($fh) ) {
        chomp $public_html_symlink;

        my @clean_path_components = Cpanel::Path::Safety::safe_get_path_components($public_html_symlink);
        my $safe_public_html_path = join( '/', @clean_path_components );

        next unless $safe_public_html_path =~ /^\/home\/virtual\//;

        #
        # Clean up the directory hierarchy up to the point just prior to the
        # /home/virtual component.
        #
        # As we need to work from the end of the @clean_path_components stack
        # downwards to obtain each absolute directory component to unlink()
        # in the appropriate order, this C-style loop is somewhat necessary.
        # Note the use of the inclusive range.
        #
        while ( scalar @clean_path_components > 2 ) {
            my $subpath = join( '/', @clean_path_components );
            last if ( $subpath eq '/home/virtual' );

            if ( -l $subpath ) {
                unlink $subpath;
            }
            elsif ( -d $subpath ) {
                rmdir $subpath;
            }

            pop @clean_path_components;
        }
    }

    close($fh);
    return unlink($public_html_symlinks);
}

sub _check_for_leftover_files_and_notify_admin {
    my (%OPTS) = @_;

    my $uid        = $OPTS{'uid'};
    my $gid        = $OPTS{'gid'};
    my $owner      = $OPTS{'owner'};
    my $user       = $OPTS{'user'};
    my $output_ref = $OPTS{'output_ref'};
    my $cpconf_ref = Cpanel::Config::LoadCpConf::loadcpconf();

    if ( defined $cpconf_ref->{'max_disk_usage_after_account_removal'} && $cpconf_ref->{'max_disk_usage_after_account_removal'} >= 0 ) {
        $$output_ref .= Whostmgr::UI::setstatusdone();
        $$output_ref .= Whostmgr::UI::setstatus("Checking for leftover files");

        # This forces a rebuild of the quota caches
        my $repquota        = Cpanel::SysQuota::fetch_system_repquota( 0, 0 );
        my $backup_dirs_ref = Cpanel::Backup::Config::get_backup_dirs();

        my $skip       = 0;
        my $used_space = 0;
        foreach my $ln ( split( /\n/, $repquota ) ) {

            foreach my $backupdir ( @{$backup_dirs_ref} ) {
                my $backupdir_regex = qr{^\*\*\*.*(?:backup|\Q$backupdir\E)};
                if ( !$backupdir || $backupdir eq '/' ) {
                    $backupdir_regex = qr{^\*\*\*.*backup};
                }
                if ( $ln =~ $backupdir_regex ) {
                    $skip = 1;
                }
            }
            if ($skip) {
                if ( $ln =~ /^\*\*\*/ ) {
                    $skip = 0;
                }
            }
            elsif ( $ln =~ /^(?:#$uid|$user)\s+[-+]{2}\s+(\d+)\s+\d+\s+\d+/ ) {
                $used_space += $1;
            }
        }

        if ( $used_space > $cpconf_ref->{'max_disk_usage_after_account_removal'} ) {

            $$output_ref .= "\nFound $used_space bytes of disk usage and only $cpconf_ref->{max_disk_usage_after_account_removal} bytes are allowed after account removal.\n";
            $$output_ref .= "Running cleanup script in the background.\n";
            my @args = ( '--notify', '--background', '--username=' . $user, $uid . ':' . $gid, Cpanel::Filesys::Home::get_all_homedirs() );
            if ( $owner && $owner ne 'root' ) {
                my ( $owner_uid, $owner_gid ) = ( Cpanel::PwCache::getpwnam($owner) )[ 2, 3 ];
                if ( defined $owner_uid && defined $owner_gid ) {
                    unshift @args, '--reassign-username=' . $owner, '--reassign=' . $owner_uid . ':' . $owner_gid;
                }
            }

            $$output_ref .= Cpanel::SafeRun::Simple::saferun( '/usr/local/cpanel/bin/reassign_post_terminate_cruft', @args );
        }
        elsif ($used_space) {
            $$output_ref .= "\nFound $used_space bytes of disk usage following account removal.\n";
            $$output_ref .= "No action required since $cpconf_ref->{max_disk_usage_after_account_removal} bytes are allowed.\n";
        }
        else {
            $$output_ref .= "\nNo disk usage found after account removal.\n";
        }
    }
    return 1;
}

sub _locale {
    require Cpanel::Locale;
    return ( $locale ||= Cpanel::Locale->get_handle() );
}

1;
