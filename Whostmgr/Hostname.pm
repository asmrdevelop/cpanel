package Whostmgr::Hostname;

# cpanel - Whostmgr/Hostname.pm                    Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Try::Tiny;

use Cpanel::Finally                      ();
use Cpanel::Sys::Uname                   ();
use Cpanel::Config::userdata             ();
use Cpanel::Config::Httpd::EA4           ();
use Cpanel::FileUtils::Open              ();
use Cpanel::FileUtils::Write             ();
use Cpanel::ConfigFiles                  ();
use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::Config::userdata::Load       ();
use Cpanel::Daemonizer::Tiny             ();
use Cpanel::Server::Type                 ();
use Cpanel::EA4::Conf                    ();
use Cpanel::FindBin                      ();
use Cpanel::Binaries                     ();
use Cpanel::InterfaceLock                ();
use Cpanel::IP::CpRapid                  ();
use Cpanel::LoadFile                     ();
use Cpanel::LoadModule                   ();
use Cpanel::Logger                       ();
use Cpanel::MailTools                    ();
use Cpanel::MailTools::DBS               ();
use Cpanel::MysqlUtils::Service          ();
use Cpanel::OS                           ();
use Cpanel::SafeFile                     ();
use Cpanel::SafeRun::Errors              ();
use Cpanel::SafeRun::Object              ();
use Cpanel::SafeRun::Simple              ();
use Cpanel::SafeRun::Timed               ();
use Cpanel::StringFunc::Case             ();
use Cpanel::Sys::Hostname                ();
use Cpanel::WebVhosts::AutoDomains       ();
use Cpanel::Validate::Hostname           ();
use Cpanel::ServerTasks                  ();

my $logger = Cpanel::Logger->new();

sub sethostname {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ( $hostname, $nohtml ) = @_;

    # Only one sethostname can be running at a time. This lock is used to block access to the
    # sethostname functionality until the previous sethostname completes all its async tasks.
    my $global_lock = Cpanel::InterfaceLock->new( name => 'UpdateHostname', unlock_on_destroy => 0 );
    my $ret         = $global_lock->lock();
    if ( $ret == -1 ) {
        return ( 0, "Cannot set the hostname; there is already hostname change in progress." );
    }
    elsif ( !$ret ) {
        return ( 0, "Cannot set the hostname; failed to acquire an interface lock for the hostname change." );
    }

    my $unlock_on_fail = Cpanel::Finally->new(
        sub {
            $global_lock->unlock();
        }
    );

    my @warnings;
    my @msgs;
    $hostname = Cpanel::StringFunc::Case::ToLower($hostname);    # needs to be lowercase for service compat .. see case 53629
    my $hostlen = length $hostname;
    if ( $hostlen > 60 ) {
        return ( 0, "Cannot set the hostname; Hostnames are limited to 60 characters (this name is $hostlen characters)" );
    }

    if ( !Cpanel::Validate::Hostname::is_valid($hostname) ) {
        return ( 0, "$hostname is not a valid hostname", ["Please refer to RFCs 952 and 1123 to determine valid hostname."] );
    }

    foreach my $autodomain ( Cpanel::WebVhosts::AutoDomains::ALL_POSSIBLE_AUTO_DOMAINS() ) {
        if ( rindex( $hostname, "$autodomain.", 0 ) == 0 ) {
            return ( 0, "The hostname may not begin with “$autodomain.” because it conflicts with an automatically configured domain." );
        }
    }

    if ( my $current_hostname_owner = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $hostname, { 'default' => '' } ) ) {
        return ( 0, "The domain “$hostname” is already owned by the user “$current_hostname_owner”.  The system cannot set the hostname to a domain owned by a user because all local email would be directed to the “$current_hostname_owner” account." );
    }

    my $old_hostname = Cpanel::Sys::Hostname::gethostname();

    # Strip off short hostname
    my ( undef, @hostnameparts ) = split( /\./, $hostname );
    my $domainname  = join( '.', @hostnameparts );
    my @html_output = ( $nohtml ? () : ('--html') );

    my $userdata_main          = Cpanel::Config::userdata::Load::load_userdata_main('nobody');
    my $hostname_from_userdata = $userdata_main->{'main_domain'} || $old_hostname;

    if ( $hostname eq $old_hostname ) {
        push @warnings, "The hostname was already set to $hostname, syncing configuration only.";
        if ( $hostname ne $hostname_from_userdata ) {
            push @warnings, "The user data was set to “$old_hostname” it will be updated to “$hostname”.";
        }
    }

    my ( $change_ok, $hostname_bin, @args_for_hostname_bin ) = determine_hostname_bin_and_args($hostname);
    $hostname = $old_hostname if !$change_ok;

    my $mysql_active;
    if ($change_ok) {

        # We need to stop MySQL during a hostname change to make it's pid/log files change.
        $mysql_active = Cpanel::MysqlUtils::Service::is_mysql_active();
        if ($mysql_active) {
            push @msgs, "Stopping cPHulkd during hostname change";
            push @msgs, Cpanel::SafeRun::Errors::saferunallerrors( '/usr/local/cpanel/scripts/restartsrv_cphulkd', '--stop', @html_output );

            push @msgs, "Stopping MySQL during hostname change";
            my $shutdown = Cpanel::MysqlUtils::Service::safe_shutdown_local_mysql();
            if ( !$shutdown ) {
                push @warnings, "Could not shut down MySQL. You will need to restart MySQL manually after a hostname change.";
                $logger->warn("Could not shut down MySQL. You will need to restart MySQL manually after a hostname change.");
            }
        }

        # Set kernel hostname
        push @msgs, "Changing hostname in kernel to $hostname";
        my $hostname_ret = Cpanel::SafeRun::Errors::saferunallerrors( $hostname_bin, @args_for_hostname_bin );
        if ( $? >> 8 != 0 ) {
            my $error = scalar $! || 'Could not execute hostname binary';
            push @warnings, "Error setting new hostname: $error";
        }
        push @warnings, $hostname_ret if $hostname_ret;

        # should not use hostnamectl here
        my $hostname_sysbin = Cpanel::Binaries::path('hostname');
        chomp( $hostname = Cpanel::SafeRun::Simple::saferun($hostname_sysbin) );
        if ( $hostname !~ /\./ ) {
            chomp( $hostname = Cpanel::SafeRun::Simple::saferun( $hostname_sysbin, '-f' ) );
            if ( $hostname eq '' || $hostname !~ /\./ ) {
                $change_ok = 0;
                $hostname  = $old_hostname;
            }
        }
    }

    # We could have fails in the above block so we
    # need to check again if the change is ok before proceeding
    if ($change_ok) {

        # Ensure the cache is reset
        Cpanel::Sys::Uname::clearcache();
        $Cpanel::Sys::Hostname::cachedhostname = '';
        if (
            _update_sysconfig_file(
                'domainname' => $domainname,
                'hostname'   => $hostname,
            )
        ) {
            push @msgs, "Altered hostname in " . Cpanel::OS::sysconfig_network();
        }

        _fix_etc_hosts();
        if ( -e '/etc/cloud/cloud.cfg.d' ) {
            _create_hostname_cloudcfg();
        }

        my @tasks;
        if ($mysql_active) {
            push @tasks, 'restartsrv mysql';
        }

        push @msgs, "Updating cPHulkd\n";
        push @msgs, Cpanel::SafeRun::Timed::timedsaferun_allerrors( 60, '/usr/local/cpanel/bin/hulkdsetup' );

        push @msgs, "Updating mailman\n";
        push @msgs, _update_mailman_default_hostname($hostname);

        push @msgs, _update_munin_conf( $old_hostname, $hostname );

        push @msgs,  "Starting cPHulkd\n";
        push @tasks, 'restartsrv cphulkd';
        push @msgs,  "Restarting Exim\n";
        push @tasks, 'restartsrv exim';
        Cpanel::ServerTasks::queue_task( ['CpServicesTasks'], @tasks );

        _set_hostname_in_wwwacct( 'hostname' => $hostname );

        if ( Cpanel::Config::Httpd::EA4::is_ea4() ) {

            # Update servername in ea4.conf. Must happen after wwwacct hostname update.
            Cpanel::EA4::Conf->new->save();
        }

        # Update Apache ServerName
        if ( !Cpanel::Server::Type::is_dnsonly() ) {
            if ($hostname_from_userdata) {
                my $nobody = Cpanel::OS::nobody();
                if ( Cpanel::Config::userdata::Load::user_exists($nobody) ) {
                    Cpanel::Config::userdata::update_domain_name_data( { 'user' => $nobody, 'old_domain' => $hostname_from_userdata, 'new_domain' => $hostname, 'update_main_domain' => 1 } );
                }
                else {
                    push @warnings, qq{Unable to update ServerName in Apache configuration. User '$nobody' has no userdata file.};
                }
            }
            else {
                push @warnings, qq{Unable to update ServerName in Apache configuration. Unable to determine old hostname.};
            }

            if ( $hostname ne $old_hostname ) {

                # This must happen before checkallsslcerts run
                _rebuild_httpdconf();
            }
        }

        my $cpkeyclt = _forked_cpkeyclt();

        push @msgs, $cpkeyclt;

        #
        #    check_unreliable_resolvers & checkallsslcerts
        #   happen in the background since they take a while
        #
        Cpanel::Daemonizer::Tiny::run_as_daemon(
            sub {
                local $SIG{'__DIE__'}  = 'DEFAULT';
                local $SIG{'__WARN__'} = 'DEFAULT';

                ####
                # The next two calls are unchecked because it cannot be captured when running as a daemon
                Cpanel::FileUtils::Open::sysopen_with_real_perms(
                    \*STDERR,
                    "$Cpanel::ConfigFiles::CPANEL_ROOT/logs/error_log",
                    'O_WRONLY|O_APPEND|O_CREAT',
                    0600,
                );

                open( STDOUT, '>>&', \*STDERR ) || warn "Failed to redirect STDOUT to STDERR";

                system( '/usr/local/cpanel/scripts/check_unreliable_resolvers', '--notify' );

                system( '/usr/local/cpanel/bin/checkallsslcerts', '--verbose' );

                return;
            }
        );

        #
        #  cpkeyclt will auto re-provision on the second run
        #  if the id changes
        #
        my $run = Cpanel::SafeRun::Object->new(
            'program' => '/usr/local/cpanel/scripts/try-later',
            'args'    => [
                '--action',      '/usr/local/cpanel/cpkeyclt --quiet',
                '--check',       '/bin/sh -c exit 1',
                '--delay',       11,                                     # We only allow updates every 10 minutes so wait 11
                '--max-retries', 1,
                '--skip-first'
            ]
        );
        push @warnings, $run->autopsy() if $run->CHILD_ERROR;

        @msgs     = grep { length } @msgs;
        @warnings = grep { length } @warnings;

        if ( $hostname ne $old_hostname ) {

            # Update /etc/localdomains
            Cpanel::MailTools::removedomain($old_hostname);
        }
        #
        # No need to update_proxy_subdomains as there should never be one for the hostname
        #
        Cpanel::MailTools::DBS::setup( $hostname, 'localdomains' => 1, 'remotedomains' => -1, 'secondarymx' => -1, 'update_proxy_subdomains' => 0 );

        require Whostmgr::Hostname::DNS;
        my ( $status, $statusmsg ) = Whostmgr::Hostname::DNS::ensure_dns_for_hostname();
        if ($status) {
            push @msgs, $statusmsg;
        }
        else {
            push @warnings, $statusmsg;
        }

        require Cpanel::DKIM;
        require Cpanel::DKIM::Transaction;
        if ( !Cpanel::DKIM::get_domain_private_key($hostname) ) {
            my $dkim = Cpanel::DKIM::Transaction->new();
            my @w;
            my $result = do {
                local $SIG{'__WARN__'} = sub { push @w, @_ };
                $dkim->set_up_user_domains( 'root', [$hostname] );
            };
            $dkim->commit();
            if ( !$result || !$result->was_any_success() ) {
                push @warnings, qq{Failed to set up DKIM: @w};
            }
        }

        push @msgs, "Gracefully restarting queueprocd...";

        push @msgs, Cpanel::SafeRun::Errors::saferunallerrors(
            qw(
              /usr/local/cpanel/scripts/restartsrv_queueprocd --graceful
            )
        );

        # If $old_hostname is actually the current hostname, then we
        # shouldn’t create an entry in the hostname-history datastore
        # because that entry would be redundant.
        #
        if ( $old_hostname ne Cpanel::Sys::Hostname::gethostname() ) {
            eval {
                require Whostmgr::Hostname::History::Write;
                my $history_writer = Whostmgr::Hostname::History::Write->new();
                $history_writer->append($old_hostname);
                $history_writer->save_or_die();
                $history_writer->close_or_die();
            };

            if ( my $exception = $@ ) {
                push @msgs, "The hostname has changed; however recording the old hostname in the change history has failed: $exception";
            }

        }

        return ( 1, "Hostname set to: $hostname", \@warnings, \@msgs );
    }

    return ( 0, "The hostname could not be changed. The server retained its previous hostname, $hostname.", \@warnings, \@msgs );
}

sub set_autodomain_hostname {
    my $hostname = Cpanel::IP::CpRapid::get_hostname();

    my $run;
    if ( $ENV{'CPANEL_BASE_INSTALL'} ) {

        # We can not use set_hostname during the installation process,
        # as it assumes that the system is in the 'post-install' stage.
        #
        # We can use system tools to set the hostname here as the 'additional'
        # tasks that set_hostname does will be done later on during the installation process.
        my ( $change_ok, $hostname_bin, @args_for_hostname_bin ) = determine_hostname_bin_and_args($hostname);
        if ($change_ok) {
            $run = Cpanel::SafeRun::Object->new(
                'program' => $hostname_bin,
                'args'    => \@args_for_hostname_bin,
                'stdout'  => \*STDOUT,
                'stderr'  => \*STDERR,
            );
        }
    }
    else {
        $run = Cpanel::SafeRun::Object->new(
            'program' => '/usr/local/cpanel/bin/set_hostname',
            'args'    => [$hostname],
            'stdout'  => \*STDOUT,
            'stderr'  => \*STDERR,
        );
    }

    # $run can be undefined if we somehow end up in a situation where we
    # couldn't find a hostname binary during installation.
    if ( !$run || $run->CHILD_ERROR() ) {
        warn $run->autopsy() if $run;
        return 0;
    }

    return $hostname;
}

sub _rebuild_httpdconf {

    # This must happen before checkallsslcerts run
    # update httpd.conf and restart
    Cpanel::SafeRun::Errors::saferunallerrors('/usr/local/cpanel/scripts/rebuildhttpdconf');
    Cpanel::SafeRun::Errors::saferunallerrors('/usr/local/cpanel/scripts/restartsrv_httpd');
    return;
}

# Ensure that the hostname is preserved on systems running cloud-init
sub _create_hostname_cloudcfg {

    return if !-e '/etc/cloud' || !-e '/etc/cloud/cloud.cfg.d';

    my $config_path = '/etc/cloud/cloud.cfg.d/99-preserve-hostname.cfg';

    open my $config_fh, '>', $config_path or die "Could not write to $config_path: $!";
    print {$config_fh} "preserve_hostname: true\nmanage_etc_hosts: false\n";
    close($config_fh);

    chmod 0700, $config_path;

    return;
}

sub _update_sysconfig_file (%opts) {
    my ( $domainname, $hostname ) = @opts{qw(domainname hostname)};

    my $sysconfig_file = Cpanel::OS::sysconfig_network();

    return unless defined $sysconfig_file;

    if ( -f $sysconfig_file && open( my $network_fh, '<', $sysconfig_file ) ) {
        my @NETWORK = <$network_fh>;
        close $network_fh;

        chomp @NETWORK;

        my $networklock = Cpanel::SafeFile::safeopen( my $fh, '>', $sysconfig_file );
        if ( !$networklock ) {
            $logger->warn("Could not write to $sysconfig_file");
            return;
        }
        foreach my $line (@NETWORK) {
            next if $line =~ m/^HOSTNAME=/i;
            next if $line =~ m/^DOMAINNAME=/i;

            print {$fh} "$line\n";
        }

        print {$fh} "HOSTNAME=$hostname\n";
        print {$fh} "DOMAINNAME=$domainname\n";

        Cpanel::SafeFile::safeclose( $fh, $networklock );

        return 1;
    }

    return;
}

sub _fix_etc_hosts {
    system('/usr/local/cpanel/scripts/fixetchosts');
    return;
}

sub _set_hostname_in_wwwacct {
    my (%opts)     = @_;
    my ($hostname) = @opts{qw(hostname)};

    if ( open my $wwwacctconf_fh, '<', '/etc/wwwacct.conf' ) {
        my @WWWACCTCONF = <$wwwacctconf_fh>;
        close $wwwacctconf_fh;
        my $wwwacctconflock = Cpanel::SafeFile::safeopen( \*WWWACCTCONF, '>', '/etc/wwwacct.conf' );
        if ( !$wwwacctconflock ) {
            $logger->warn("Could not write to /etc/wwwacct.conf");
            return;
        }
        foreach (@WWWACCTCONF) {
            if (/^HOST\s+/) {
                print WWWACCTCONF "HOST $hostname\n";
            }
            else {
                print WWWACCTCONF;
            }
        }
        Cpanel::SafeFile::safeclose( \*WWWACCTCONF, $wwwacctconflock );
    }
    return;
}

sub _forked_cpkeyclt {
    my $cpkeyclt;
    if ( open( my $cpkeyclt_fh, '-|' ) ) {
        while ( readline($cpkeyclt_fh) ) {
            $cpkeyclt .= $_;
        }
        close $cpkeyclt_fh;
    }
    else {
        exec '/usr/local/cpanel/cpkeyclt', '--force-no-tty-check' or exit(1);
    }
    return $cpkeyclt;
}

sub determine_hostname_bin_and_args {
    my $hostname = shift;

    my $change_ok = 1;
    my ( $hostname_bin, @args_for_hostname_bin );
    if ( $hostname_bin = Cpanel::FindBin::findbin('hostnamectl') ) {

        # CentOS 7 logic
        @args_for_hostname_bin = ( 'set-hostname', $hostname );

    }
    elsif ( -x ( $hostname_bin = Cpanel::Binaries::path('hostname') ) ) {

        # CentOS 5/6 logic
        @args_for_hostname_bin = ($hostname);
    }
    else {
        $change_ok = 0;
    }

    return ( $change_ok, $hostname_bin, @args_for_hostname_bin );
}

sub _update_mailman_default_hostname {
    my ($hostname) = @_;
    Cpanel::SafeRun::Errors::saferunallerrors( "$Cpanel::ConfigFiles::MAILMAN_ROOT/bin/withlist", '-l', '-r', 'fix_url', 'mailman', "--urlhost=$hostname" );
    return;
}

sub _update_munin_conf {
    my ( $old_hostname, $new_hostname ) = @_;

    my $conf_file = '/etc/munin/munin.conf';

    if ( -e $conf_file ) {
        my $munin_conf_data = Cpanel::LoadFile::loadfile($conf_file);
        $munin_conf_data =~ s{\Q$old_hostname\E}{$new_hostname}g;
        Cpanel::FileUtils::Write::overwrite( $conf_file, $munin_conf_data, 0644 );

        Cpanel::SafeRun::Errors::saferunallerrors('/usr/local/cpanel/bin/build_munin_conf');

        return "Updated munin.conf\n";
    }

    return;
}

1;
