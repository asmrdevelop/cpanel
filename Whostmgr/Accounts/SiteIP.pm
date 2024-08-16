package Whostmgr::Accounts::SiteIP;

# cpanel - Whostmgr/Accounts/SiteIP.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Cpanel::Template::Ftp                      ();
use Cpanel::AcctUtils::Account                 ();
use Cpanel::PwCache                            ();
use Cpanel::Config::CpUserGuard                ();
use Cpanel::Config::Httpd::IpPort              ();
use Cpanel::Config::userdata                   ();
use Cpanel::DIp::IsDedicated                   ();
use Cpanel::DIp::MainIP                        ();
use Cpanel::DomainIp                           ();
use Cpanel::Finally                            ();
use Cpanel::FtpUtils::Config::Proftpd::CfgFile ();
use Cpanel::FtpUtils::Server                   ();
use Cpanel::DnsUtils::AskDnsAdmin              ();
use Cpanel::HttpUtils::ApRestart::BgSafe       ();
use Cpanel::HttpUtils::Config::Apache          ();
use Cpanel::IpPool                             ();
use Cpanel::Ips::Fetch                         ();
use Cpanel::Debug                              ();
use Cpanel::NAT                                ();
use Cpanel::SafeFile                           ();
use Cpanel::Transaction::File::Raw             ();
use Cpanel::Validate::IP                       ();
use Cpanel::Userdomains                        ();
use Cpanel::ServerTasks                        ();
use Whostmgr::DNS::Domains                     ();
use Whostmgr::DNS::ZoneIP                      ();
use Cpanel::Config::WebVhosts                  ();
use Cpanel::Config::userdata::Load             ();

use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics
use Cpanel::Hooks ();
use Cwd           ();

#XXX At least one test of this function is *very* presumptive about
#the implementation internals. Any refactoring is like to trip a
#spurious breakage in that logic.
sub set {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ( $user, $oldip, $newip, $quiet ) = @_;

    if ( -e '/var/cpanel/ipmigratelock' ) {
        return 0, 'You cannot change IP addresses while an ip migration is in progress';
    }

    require Cpanel::Rlimit;
    Cpanel::Rlimit::set_rlimit_to_infinity();

    my $addr         = Cpanel::DIp::MainIP::getmainip();
    my $user_homedir = Cpanel::PwCache::gethomedir($user) or do {
        return 0, 'Invalid user: ' . $user;
    };
    my $abshomedir   = Cwd::abs_path($user_homedir);
    my $cpuser_guard = Cpanel::Config::CpUserGuard->new($user);
    my $cpuser_data  = $cpuser_guard->{'data'};
    my $domain       = $cpuser_data->{'DOMAIN'};
    my $owner        = $cpuser_data->{'OWNER'};
    my $issharedip   = 0;
    my $ips          = Cpanel::Ips::Fetch::fetchipslist();

    $oldip //= Cpanel::DomainIp::getdomainip($domain);

    if ($oldip) {
        $oldip =~ s/[\t\s\n]*//g;
    }
    if ( !defined $user || length $user < 1 ) {
        return 0, 'Cannot determine username';
    }
    elsif ( !$oldip ) {
        return 0, "The system could not determine the current IP address for “$user”";
    }
    elsif ( !$newip ) {
        return 0, "The system could not determine the new IP address for “$domain ($user)”";
    }
    elsif ( $newip eq $oldip ) {
        return 1, "$domain is already using ip " . Cpanel::NAT::get_public_ip($newip);
    }
    elsif ( !Cpanel::Validate::IP::is_valid_ip($newip) ) {
        return 0, "The specified IP address “$newip” is invalid.";
    }
    elsif ( scalar %$ips && !exists $ips->{$newip} ) {
        return 0, 'Unable to set to an unconfigured ip address';
    }

    if ( !Cpanel::AcctUtils::Account::accountexists($user) ) {
        return 0, 'Account does not exist.';
    }

    my ( $hook_result, $hook_msgs ) = Cpanel::Hooks::hook(
        {
            'category' => 'Whostmgr',
            'event'    => "Accounts::SiteIP::set",
            'stage'    => 'pre',
            'blocking' => 1,
        },
        {
            'user'             => $user,
            'original_address' => $oldip,
            'new_address'      => $newip,
        },
    );
    my $hooks_msg = int @{$hook_msgs} ? join "\n", @{$hook_msgs} : '';
    if ( !$hook_result ) {
        return ( 0, "Hook denied setting account IP Address: $hooks_msg\n" );
    }
    else {
        print "<pre>" . $hooks_msg . "</pre>" if !$quiet;
    }

    print "<h3>Changing ip for $domain ($user) to " . Cpanel::NAT::get_public_ip( ${newip} ) . "</h3>\n" if !$quiet;

    my %DNSLIST;
    print "Setting up for ip change.....\n" if !$quiet;
    {
        my $safel = Cpanel::SafeFile::safeopen( \*IPC, '>', '/var/cpanel/ipchangeinprogress' );
        if ( !$safel ) {
            Cpanel::Debug::log_warn('Could not write to /var/cpanel/ipchangeinprogress');
            return 0, 'Unable to lock system for IP address change.';
        }
        my $unlock = Cpanel::Finally->new(
            sub {
                Cpanel::SafeFile::safeclose( \*IPC, $safel );
            }
        );

        print "Done<br />\n" if !$quiet;

        if ( !Cpanel::DIp::IsDedicated::isdedicatedip($newip) ) {
            $issharedip = 1;
        }
        else {
            require Cpanel::DIp::Owner;
            my $ded_ips_hr = Cpanel::DIp::Owner::get_all_dedicated_ips();

            if ( $ded_ips_hr->{$newip} ) {
                return 0, "Sorry, " . Cpanel::NAT::get_public_ip($newip) . " is in use by another domain name and is not a shared ip.";
            }
        }

        # We fetch remote first to prime the disk cache
        # Remote Zone IP ( remote IP should not be converted in a local ip )
        my @ZF = split "\n", Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'GETZONE', 0, $domain );

        my $remotezoneip = Cpanel::NAT::get_public_ip( Whostmgr::DNS::Domains::getzoneip( $domain, @ZF ) );

        # Zone IP ( GETZONE localonly )
        my @ZONE = split "\n", Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'GETZONE', 1, $domain );

        my $zoneip = Cpanel::NAT::get_local_ip( Whostmgr::DNS::Domains::getzoneip( $domain, @ZONE ) );

        print "<pre>\n" if !$quiet;
        if ( $remotezoneip && $remotezoneip ne $oldip && !$quiet ) {
            print <<"EOM";
<span class="b2">
The remote dns zone is not consistent with the httpd.conf.
The current ip in httpd.conf is: $oldip.
The current ip in the dns zone is: $remotezoneip!
</span>
<span class="b2">$remotezoneip will be switched to the new ip as well!</span>
EOM
        }

        if ( $zoneip && $zoneip ne $oldip && !$quiet ) {
            print <<"EOM";
<span class="b2">
The local dns zone is not consistent with the httpd.conf.
The current ip in httpd.conf is: $oldip.
The current ip in the dns zone is: $zoneip!
</span>
<span class="b2">$zoneip will be switched to the new ip as well!</span>
EOM
        }

        if ( $zoneip && $remotezoneip && $remotezoneip ne $oldip && $zoneip ne $oldip && !$quiet ) {
            print <<"EOM";
<span class="b2">
<b>Warning, serious database inconsistency. httpd.conf, local dns, and remote dns all
have different ideas about what the ip address of this site really is. They will now all be changed
to the new ip: $newip!</b>
</span>
EOM
        }

        # Update userdata
        Cpanel::Config::userdata::update_domain_ip_data( $user, $domain, $newip, $Cpanel::Config::userdata::SKIP_CACHE_UPDATE );

        my $zonechanges_ref = { 'sourceip' => [$oldip], 'destip' => $newip, 'domainref' => [] };
        if ( $remotezoneip && !grep ( /^\Q$remotezoneip\E/, @{ $zonechanges_ref->{'sourceip'} } ) ) {
            push @{ $zonechanges_ref->{'sourceip'} }, $remotezoneip;
        }
        if ( $zoneip && !grep ( /^\Q$zoneip\E/, @{ $zonechanges_ref->{'sourceip'} } ) ) {
            push @{ $zonechanges_ref->{'sourceip'} }, $zoneip;
        }
        push @{ $zonechanges_ref->{'domainref'} }, $domain;

        # Update IP in cPanel user file
        $cpuser_data->{'IP'} = $newip;
        $cpuser_guard->save();

        foreach my $otherdomain ( @{ $cpuser_data->{'DOMAINS'} } ) {
            Cpanel::Config::userdata::update_domain_ip_data( $user, $otherdomain, $newip, $Cpanel::Config::userdata::SKIP_CACHE_UPDATE );
            push @{ $zonechanges_ref->{'domainref'} }, $otherdomain;
        }

        # Required for domainips to be updated correctly
        require Cpanel::Config::userdata::UpdateCache;
        eval { Cpanel::Config::userdata::UpdateCache::update($user) };
        warn if $@;

        # This will change the zone files and reload the zones
        my ( $result, $reason ) = Whostmgr::DNS::ZoneIP::changezoneip($zonechanges_ref);
        return ( $result, $reason ) if !$result;
        print $reason               if !$quiet && defined $reason;

        my $wvh         = Cpanel::Config::WebVhosts->load($user);
        my @vhost_names = ( $wvh->main_domain(), $wvh->subdomains() );

        my $httpd_port = Cpanel::Config::Httpd::IpPort::get_main_httpd_port();
        my $ssl_port   = Cpanel::Config::Httpd::IpPort::get_ssl_httpd_port();

        if (@vhost_names) {
            print "Updating httpd.conf...." if !$quiet;

            my $httpconf = apache_paths_facade->file_conf();

            my $httpd_conf_transaction = eval { Cpanel::HttpUtils::Config::Apache->new() };
            if ( !$httpd_conf_transaction ) {
                print "ERROR: $@\n";
            }

            for my $vhost_name (@vhost_names) {
                my ( $change_ok, $change_msg ) = $httpd_conf_transaction->change_vhost_ip( $vhost_name, $newip, 'std' );
                if ( !$change_ok ) {
                    warn "Attempt to update $vhost_name (non-SSL) to $newip: $change_msg\n";
                }

                if ( Cpanel::Config::userdata::Load::user_has_ssl_domain( $user, $vhost_name ) ) {
                    my ( $change_ok, $change_msg ) = $httpd_conf_transaction->change_vhost_ip( $vhost_name, $newip, 'ssl' );
                    if ( !$change_ok ) {
                        warn "Attempt to update $vhost_name (SSL) to $newip: $change_msg\n";
                    }
                }
            }

            my ( $change_ok, $change_msg ) = $httpd_conf_transaction->save();

            if ($change_ok) {
                my ( $close_ok, $close_msg ) = $httpd_conf_transaction->close();
                if ($close_ok) {
                    print "Done\n" if !$quiet;
                }
                else {    #This seems unlikely ever to happen.
                    print "ERROR on close(): $close_msg\n";
                }
            }
            else {
                print "ERROR: $change_msg\n";
                my ( $abort_ok, $abort_msg ) = $httpd_conf_transaction->abort();
                if ( !$abort_ok ) {
                    print "ERROR on abort(): $abort_msg\n";
                }
            }
        }

        # TODO: Move this into Cpanel::FtpUtils::Config::Proftpd::Vhosts
        if ( Cpanel::FtpUtils::Server::using_proftpd() ) {
            print "</pre>\nUpdating/Adding New Config Entries...." if !$quiet;
            if ( $newip ne $addr && !$issharedip ) {
                my $proftpdconf = Cpanel::FtpUtils::Config::Proftpd::CfgFile::bare_find_conf_file();

                print "..$domain (ftp)..\n" if !$quiet;

                my $ftp_trans    = Cpanel::Transaction::File::Raw->new( 'path' => $proftpdconf, perms => 0600 );
                my $conf_sr      = $ftp_trans->get_data();
                my $hasoldpvhost = $$conf_sr =~ m/^\s*<VirtualHost\s+\Q$oldip\E>$/mi ? 1 : 0;

                if ($hasoldpvhost) {
                    my @FTPCONF = split( m/^/, $$conf_sr );
                    foreach (@FTPCONF) {
                        if (m/^\s*<VirtualHost\s+\Q${oldip}\E>$/i) {
                            s/\Q${oldip}\E/${newip}/g;
                        }
                    }
                    $ftp_trans->set_data( \join( '', @FTPCONF ) );

                }
                else {
                    if ( -e '/var/cpanel/noanonftp' ) {
                        $$conf_sr .= "\n" . Cpanel::Template::Ftp::getftptemplate( 'stdvhostnoanon', 'proftpd', $domain, $newip, $user, $user_homedir ) . "\n";
                    }
                    else {
                        $$conf_sr .= "\n" . Cpanel::Template::Ftp::getftptemplate( 'stdvhost', 'proftpd', $domain, $newip, $user, $user_homedir ) . "\n";
                    }

                }
                $ftp_trans->save_and_close_or_die();
            }
            else {
                require Cpanel::FtpUtils::Proftpd::Kill;
                require Cpanel::Validate::Domain::Normalize;
                my $normal_domain = Cpanel::Validate::Domain::Normalize::normalize($domain);    # included for legacy compatiblity only
                Cpanel::FtpUtils::Proftpd::Kill::remove_servername_from_conf($normal_domain);
            }
            print "..Done\n<pre>" if !$quiet;
            if ( $newip ne $addr && !$issharedip ) {
                _restartsrv_ftp();
            }
        }
        unlink '/etc/pure-ftpd/' . $oldip;

        Cpanel::HttpUtils::ApRestart::BgSafe::restart();

        my $freeips = Cpanel::IpPool::rebuild();
        print "System has $freeips free ip" . ( $freeips == 1 ? '' : 's' ) . ".\n" if !$quiet;

    }

    Cpanel::DomainIp::clear_domain_ip_cache( keys %DNSLIST );

    require Cpanel::Userdomains::CORE;
    if ( Cpanel::Userdomains::CORE::per_domain_mailips_is_enabled() ) {

        # If per_domain_mailips is enabled we need to do
        # update_dedicated_ips_and_dependencies_or_warn before
        # updateuserdomains in case the ip change will alter
        # /etc/mailips or /etc/mailhelo
        require Cpanel::DIp::Update;
        Cpanel::DIp::Update::update_dedicated_ips_and_dependencies_or_warn();
        Cpanel::Userdomains::updateuserdomains();
    }
    else {
        my @cpdb_tasks = ( 'update_domainips_and_deps', 'update_userdomains' );
        eval { Cpanel::ServerTasks::queue_task( ['CpDBTasks'], @cpdb_tasks ) };
        warn if $@;
    }

    print "</pre><span class=\"b2\">Account modified. New ip is: " . Cpanel::NAT::get_public_ip($newip) . ".</span>" if !$quiet;

    ( $hook_result, $hook_msgs ) = Cpanel::Hooks::hook(
        {
            'category' => 'Whostmgr',
            'event'    => "Accounts::SiteIP::set",
            'stage'    => 'post',
            'blocking' => 0,
        },
        {
            'user'             => $user,
            'original_address' => $oldip,
            'new_address'      => $newip,
        },
    );

    return ( 1, '' );
}

sub _restartsrv_ftp {
    return Cpanel::ServerTasks::schedule_task( ['CpServicesTasks'], 1, "restartsrv ftpd" );
}

1;
