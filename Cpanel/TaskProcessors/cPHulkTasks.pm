package Cpanel::TaskProcessors::cPHulkTasks;

# cpanel - Cpanel/TaskProcessors/cPHulkTasks.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule ();

{

    package Cpanel::TaskProcessors::cPHulkTasks::KnownNetblocks;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub get_dbh {
        my $self = shift;

        return $self->{'dbh'} if $self->{'dbh'} && $self->{'dbh'}->ping();
        require Cpanel::Hulk::Admin::DB;
        return $self->{'dbh'} = Cpanel::Hulk::Admin::DB::get_dbh();
    }

    sub add_known_ip_for_user {
        my ( $self, $request ) = @_;

        return if !$request->{'remote_ip'} || $request->{'ip_is_loopback'};

        my $TIMEZONESAFE_FROM_UNIXTIME = "DATETIME(?, 'unixepoch', 'localtime')";

        Cpanel::LoadModule::load_perl_module('Cpanel::IP::Convert');
        Cpanel::LoadModule::load_perl_module('Cpanel::Net::Whois::IP::Cached');
        Cpanel::LoadModule::load_perl_module('Net::CIDR');

        # Try to include the whole netblock
        my @ranges;
        my $whois_response = Cpanel::Net::Whois::IP::Cached->new()->lookup_address( $request->{'remote_ip'} );

        if ( $whois_response && ref $whois_response ) {
            #
            # The cidr attribute is an array
            #
            my $cidr_ar = $whois_response->get('cidr');

            foreach my $cidr ( @{$cidr_ar} ) {
                foreach my $range ( Net::CIDR::cidr2range($cidr) ) {
                    my ( $range_start, $range_end ) = split( m{-}, $range );
                    my $ip_bin16_startaddress = Cpanel::IP::Convert::ip2bin16($range_start);
                    my $ip_bin16_endaddress   = Cpanel::IP::Convert::ip2bin16($range_end);
                    push @ranges, [ $ip_bin16_startaddress, $ip_bin16_endaddress ];
                }
            }
        }
        else {
            # otherwise just the single address
            my $unpack = $request->{'ip_version'} == 6 ? 'B128' : 'B32';
            my $ip_bin = Cpanel::IP::Convert::ip2bin16( Cpanel::IP::Convert::binip_to_human_readable_ip( pack( $unpack, $request->{'ip_bin16'} ) ) );
            push @ranges, [ $ip_bin, $ip_bin ];
        }

        foreach my $range_ref (@ranges) {
            my ( $ip_bin16_startaddress, $ip_bin16_endaddress ) = @{$range_ref};
            $self->get_dbh()->do(
                "INSERT INTO known_netblocks (USER,STARTADDRESS,ENDADDRESS,LOGINTIME) VALUES(?,?,?,$TIMEZONESAFE_FROM_UNIXTIME); /*_add_ip_block_to_known*/",
                {},
                $request->{'user'},
                $ip_bin16_startaddress,
                $ip_bin16_endaddress,
                scalar time(),
            );
        }

        return scalar @ranges;
    }
}

{

    package Cpanel::TaskProcessors::cPHulkTasks::KnownNetblocks::PurgeOldLogins;
    use parent -norequire, 'Cpanel::TaskProcessors::cPHulkTasks::KnownNetblocks';

    my $KNOWN_NETBLOCKS_EXPIRE_TIME = '-1 YEAR';

    sub _do_child_task {
        my ($self) = @_;
        return $self->get_dbh()->do("DELETE FROM known_netblocks WHERE LOGINTIME <= DATETIME('now','localtime','$KNOWN_NETBLOCKS_EXPIRE_TIME') /*purge_old_logins*/;");
    }
}

{

    package Cpanel::TaskProcessors::cPHulkTasks::KnownNetblocks::AddIPForUser;
    use parent -norequire, 'Cpanel::TaskProcessors::cPHulkTasks::KnownNetblocks';

    sub deferral_tags {
        my ($self) = @_;
        return qw/add_known_ip_for_user/;
    }

    sub _do_child_task {
        my ($self) = @_;

        Cpanel::LoadModule::load_perl_module('Cpanel::JSON');
        Cpanel::LoadModule::load_perl_module('Cpanel::Hulkd::QueuedTasks::AddKnownIPForUser::Harvester');
        Cpanel::Hulkd::QueuedTasks::AddKnownIPForUser::Harvester->harvest(
            sub {
                return $self->add_known_ip_for_user(shift);
            }
        );
        return 1;
    }
}

{

    package Cpanel::TaskProcessors::cPHulkTasks::KnownNetblocks::Notify;
    use parent -norequire, 'Cpanel::TaskProcessors::cPHulkTasks::KnownNetblocks';

    sub deferral_tags {
        my ($self) = @_;
        return qw/notify_cphulkd/;
    }

    sub _address_in_known_netblocks_for_user {
        my ( $self, $request ) = @_;

        return 1 if $request->{'ip_is_loopback'};
        return 0 if !$request->{'remote_ip'};

        Cpanel::LoadModule::load_perl_module('Cpanel::IP::Convert');
        my $unpack   = $request->{'ip_version'} == 6 ? 'B128' : 'B32';
        my $ip_bin   = Cpanel::IP::Convert::ip2bin16( Cpanel::IP::Convert::binip_to_human_readable_ip( pack( $unpack, $request->{'ip_bin16'} ) ) );
        my $list_ref = $self->get_dbh()->selectcol_arrayref(
            "SELECT LOGINTIME from known_netblocks where STARTADDRESS <= ? and ENDADDRESS >= ? and USER=? LIMIT 1; /*_address_is_in_netblock_in_good_history*/",
            { Slice => {} },
            $ip_bin,
            $ip_bin,
            $request->{'user'},
        );

        if ( $list_ref && ref $list_ref && $list_ref->[0] ) {
            return 1;
        }

        return 0;
    }

    sub _get_whitelist_blacklist_ips {
        my ( $self, $remote_ip ) = @_;

        return if !$remote_ip;

        Cpanel::LoadModule::load_perl_module('Cpanel::Redirect');
        Cpanel::LoadModule::load_perl_module('Cpanel::Hostname');

        my $hostname = Cpanel::Hostname::gethostname();
        my $url_host = Cpanel::Redirect::getserviceSSLdomain('cpanel') || $hostname;

        my @whitelist_ips;
        my @blacklist_ips;

        push( @blacklist_ips, { range => "IP", href => "https://$url_host:2087/scripts7/cphulk/blacklist?ip=$remote_ip" } );
        push( @whitelist_ips, { range => "IP", href => "https://$url_host:2087/scripts7/cphulk/whitelist?ip=$remote_ip" } );

        Cpanel::LoadModule::load_perl_module('Cpanel::Net::Whois::IP::Cached');
        my $whois_response = Cpanel::Net::Whois::IP::Cached->new()->lookup_address($remote_ip);
        if ( $whois_response && ref $whois_response ) {

            #
            # The cidr attribute is an array
            #
            my $cidr_ar = $whois_response->get('cidr');

            foreach my $cidr ( @{$cidr_ar} ) {
                push @blacklist_ips, { 'range' => 'IANA Netblock', href => "https://$url_host:2087/scripts7/cphulk/blacklist?ip=$cidr" };
                push @whitelist_ips, { 'range' => 'IANA Netblock', href => "https://$url_host:2087/scripts7/cphulk/whitelist?ip=$cidr" };
            }
        }

        if ( $remote_ip =~ /:/ ) {
            my $ip0 = substr( $remote_ip, 0, length($remote_ip) - 1 ) . '0';
            my $ip1 = substr( $remote_ip, 0, length($remote_ip) - 2 ) . '00';
            my $ip2 = substr( $remote_ip, 0, length($remote_ip) - 3 ) . '000';
            my $ip3 = join( ':', ( split( /:/, $remote_ip ) )[ 0, 1, 2, 3, 4, 5, 6 ] ) . ':0000';
            my $ip4 = join( ':', ( split( /:/, $remote_ip ) )[ 0, 1, 2, 3, 4, 5 ] ) . ':0000:0000';
            my $ip5 = join( ':', ( split( /:/, $remote_ip ) )[ 0, 1, 2, 3, 4 ] ) . ':0000:0000:0000';
            push(
                @blacklist_ips,
                (
                    { range => "/124", href => "https://$url_host:2087/scripts7/cphulk/blacklist?ip=$ip0/124" },
                    { range => "/120", href => "https://$url_host:2087/scripts7/cphulk/blacklist?ip=$ip1/120" },
                    { range => "/116", href => "https://$url_host:2087/scripts7/cphulk/blacklist?ip=$ip2/116" },
                    { range => "/112", href => "https://$url_host:2087/scripts7/cphulk/blacklist?ip=$ip3/112" },
                    { range => "/96",  href => "https://$url_host:2087/scripts7/cphulk/blacklist?ip=$ip4/96" },
                    { range => "/80",  href => "https://$url_host:2087/scripts7/cphulk/blacklist?ip=$ip5/80" },
                )
            );

            push(
                @whitelist_ips,
                (
                    { range => "/124", href => "https://$url_host:2087/scripts7/cphulk/whitelist?ip=$ip0/124" },
                    { range => "/120", href => "https://$url_host:2087/scripts7/cphulk/whitelist?ip=$ip1/120" },
                    { range => "/116", href => "https://$url_host:2087/scripts7/cphulk/whitelist?ip=$ip2/116" },
                    { range => "/112", href => "https://$url_host:2087/scripts7/cphulk/whitelist?ip=$ip3/112" },
                    { range => "/96",  href => "https://$url_host:2087/scripts7/cphulk/whitelist?ip=$ip4/96" },
                    { range => "/80",  href => "https://$url_host:2087/scripts7/cphulk/whitelist?ip=$ip5/80" },
                )
            );
        }
        else {
            my $ip0 = join( '.', ( split( /\./, $remote_ip ) )[ 0, 1, 2 ] ) . '.0';
            my $ip1 = join( '.', ( split( /\./, $remote_ip ) )[ 0, 1 ] ) . '.0.0';
            push(
                @blacklist_ips,
                (
                    { range => "/24", href => "https://$url_host:2087/scripts7/cphulk/blacklist?ip=$ip0/24" },
                    { range => "/16", href => "https://$url_host:2087/scripts7/cphulk/blacklist?ip=$ip1/16" },
                )
            );
            push(
                @whitelist_ips,
                (
                    { range => "/24", href => "https://$url_host:2087/scripts7/cphulk/whitelist?ip=$ip0/24" },
                    { range => "/16", href => "https://$url_host:2087/scripts7/cphulk/whitelist?ip=$ip1/16" },
                )
            );
        }

        return \@blacklist_ips, \@whitelist_ips;
    }

    sub _request_report_return_ar {
        my ( $self, $request ) = @_;

        my $locale;
        Cpanel::LoadModule::load_perl_module('Cpanel::AcctUtils::Account');
        Cpanel::LoadModule::load_perl_module('Cpanel::Locale');

        if ( Cpanel::AcctUtils::Account::accountexists( $request->{'user'} ) ) {
            Cpanel::LoadModule::load_perl_module('Cpanel::Locale::Utils::User');
            $locale = Cpanel::Locale->get_handle( Cpanel::Locale::Utils::User::get_user_locale( $request->{'user'} ) );
        }
        else {
            $locale = Cpanel::Locale->new();
        }

        my @data;
        my %REQUEST_KEY_HUMAN_READABLE_NAMES = _REQUEST_KEY_HUMAN_READABLE_NAMES();

        foreach my $key ( sort keys %REQUEST_KEY_HUMAN_READABLE_NAMES ) {
            my $value = $request->{$key} or next;
            my $name  = $REQUEST_KEY_HUMAN_READABLE_NAMES{$key};
            $value =~ s/\s//g;
            next if !$value;
            push @data, { 'name' => $name->to_string(), 'value' => $value };
        }

        return \@data;
    }

    sub _REQUEST_KEY_HUMAN_READABLE_NAMES {
        Cpanel::LoadModule::load_perl_module('Cpanel::LocaleString');
        return (
            'remote_ip'   => Cpanel::LocaleString->new('Remote IP Address'),
            'local_ip'    => Cpanel::LocaleString->new('Local IP Address'),
            'service'     => Cpanel::LocaleString->new('Authentication Database'),
            'authservice' => Cpanel::LocaleString->new('Service'),
            'user'        => Cpanel::LocaleString->new('Username'),
            'local_port'  => Cpanel::LocaleString->new('Local Port'),
            'remote_port' => Cpanel::LocaleString->new('Remote Port'),
            'local_user'  => Cpanel::LocaleString->new('Local User triggering request'),

            # For debug only
            #    'authtoken_hash' => Cpanel::LocaleString->can('new')->('Cpanel::LocaleString', 'Hashed Auth Token'),
        );
    }

}

{

    package Cpanel::TaskProcessors::cPHulkTasks::KnownNetblocks::NotifyLogin;
    use parent -norequire, 'Cpanel::TaskProcessors::cPHulkTasks::KnownNetblocks::Notify';

    sub deferral_tags {
        my ($self) = @_;
        return qw/notify_cphulkd/;
    }

    sub _do_child_task {
        my ( $self, $task ) = @_;

        Cpanel::LoadModule::load_perl_module('Cpanel::Hulkd::QueuedTasks::NotifyLogin::Harvester');
        Cpanel::Hulkd::QueuedTasks::NotifyLogin::Harvester->harvest(
            sub {
                return $self->notify_login(shift);
            }
        );
        return 1;
    }

    sub notify_login {
        my ( $self, $data_hr ) = @_;

        my $request     = $data_hr->{'request'};
        my $notify_opts = $data_hr->{'notify_opts'};

        my $address_is_known = $self->_address_in_known_netblocks_for_user($request);
        return if $address_is_known && !$notify_opts->{'notify_on_login_from_known_netblock'};

        Cpanel::LoadModule::load_perl_module('Cpanel::iContact::Class::cPHulk::Login');

        my ( $blacklist, $whitelist ) = $self->_get_whitelist_blacklist_ips( $request->{'remote_ip'} );
        my ( $domain, @additional_args );
        if ( $request->{'user'} =~ m{@} ) {
            $domain = ( split( '@', $request->{'user'}, 2 ) )[-1];

            require Cpanel::AcctUtils::DomainOwner::Tiny;
            my $domain_owner = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $domain, { 'default' => q{} } );
            @additional_args = (
                'to'                                => $request->{'user'},
                'username'                          => $domain_owner,
                'notification_targets_user_account' => 1,
            );
        }
        elsif ( $request->{'user'} eq 'root' ) {
            Cpanel::LoadModule::load_perl_module('Cpanel::Hostname');
            $domain          = Cpanel::Hostname::gethostname();
            @additional_args = ();
        }
        else {
            Cpanel::LoadModule::load_perl_module('Cpanel::AcctUtils::Domain');
            $domain          = Cpanel::AcctUtils::Domain::getdomain( $request->{'user'} );
            @additional_args = (
                'to'                                => $request->{'user'},
                'username'                          => $request->{'user'},
                'notification_targets_user_account' => 1,
            );
        }

        Cpanel::LoadModule::load_perl_module('Cpanel::Notify');
        Cpanel::Notify::notification_class(
            'class'            => 'cPHulk::Login',
            'application'      => 'cPHulk::Login',
            'constructor_args' => [
                @additional_args,
                user              => $request->{'user'},
                user_domain       => $domain,
                origin            => $request->{'authservice'},
                source_ip_address => $request->{'remote_ip'},
                report            => $self->_request_report_return_ar($request),
                is_root           => $notify_opts->{'is_root'},
                is_local          => $notify_opts->{'is_local'},
                whitelist_ips     => $whitelist,
                blacklist_ips     => $blacklist,
                known_netblock    => $address_is_known,
            ]
        );

        $self->add_known_ip_for_user($request) if !$address_is_known;

        return 1;
    }
}

{

    package Cpanel::TaskProcessors::cPHulkTasks::KnownNetblocks::NotifyBrute;
    use parent -norequire, 'Cpanel::TaskProcessors::cPHulkTasks::KnownNetblocks::Notify';

    sub deferral_tags {
        my ($self) = @_;
        return qw/notify_cphulkd/;
    }

    sub _do_child_task {
        my ( $self, $task ) = @_;

        Cpanel::LoadModule::load_perl_module('Cpanel::JSON');
        my $request     = Cpanel::JSON::Load( $task->get_arg(0) );
        my $notify_opts = Cpanel::JSON::Load( $task->get_arg(1) );

        Cpanel::LoadModule::load_perl_module('Cpanel::iContact::Class::cPHulk::BruteForce');
        my ( $blacklist, $whitelist ) = $self->_get_whitelist_blacklist_ips( $request->{'remote_ip'} );

        Cpanel::LoadModule::load_perl_module('Cpanel::Notify');
        Cpanel::Notify::notification_class(
            'class'            => 'cPHulk::BruteForce',
            'application'      => 'cPHulk::BruteForce',
            'constructor_args' => [
                user                 => $request->{'user'},
                origin               => $request->{'authservice'},
                source_ip_address    => $request->{'remote_ip'},
                report               => $self->_request_report_return_ar($request),
                current_failures     => $notify_opts->{'current_failures'},
                max_allowed_failures => $notify_opts->{'max_allowed_failures'},
                is_excessive         => $notify_opts->{'excessive_failures'},
                whitelist_ips        => $whitelist,
                blacklist_ips        => $blacklist
            ]
        );

        return 1;
    }
}

{

    package Cpanel::TaskProcessors::cPHulkTasks::KnownNetblocks::UpdateCountryIps;
    use parent -norequire, 'Cpanel::TaskProcessors::cPHulkTasks::KnownNetblocks';

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        local $@;
        eval {
            require Cpanel::GeoIPfree;
            require Cpanel::Config::Hulk;
            my $dbh                          = $self->get_dbh();
            my $last_update_country_ips_time = $dbh->selectrow_array("SELECT VALUE from config_track where ENTRY='last_update_country_ips_time';") || 0;
            my $last_dat_file_update         = ( stat($Cpanel::GeoIPfree::DAT_FILE_PATH) )[9];
            my $conf_file                    = Cpanel::Config::Hulk::get_conf_file();
            my $conf_mtime                   = ( stat($conf_file) )[9] || 0;

            if (   $last_update_country_ips_time <= $conf_mtime
                || $last_update_country_ips_time <= $last_dat_file_update ) {

                require Cpanel::Config::Hulk::Load;
                my $conf_ref       = Cpanel::Config::Hulk::Load::loadcphulkconf();
                my %list_countries = (
                    'white' => [ split( m{,}, ( $conf_ref->{'country_whitelist'} || '' ) ) ],
                    'black' => [ split( m{,}, ( $conf_ref->{'country_blacklist'} || '' ) ) ],
                );
                require Cpanel::CountryCodes::IPS;

                my %list_ranges;
                foreach my $list_type ( keys %list_countries ) {
                    foreach my $code ( @{ $list_countries{$list_type} } ) {
                        my $ip_ar = Cpanel::CountryCodes::IPS::get_ipbin16_ranges_for_code($code);
                        push @{ $list_ranges{$list_type} }, map { [ @$_, $code ] } @$ip_ar;
                    }
                }
                $dbh->do("BEGIN TRANSACTION;");
                my $insert_q = $dbh->prepare("INSERT OR IGNORE INTO ip_lists (STARTADDRESS,ENDADDRESS,TYPE,COMMENT) VALUES (?,?,?,?);");
                foreach my $list_type ( keys %list_countries ) {
                    my $key = $list_type eq 'white' ? $Cpanel::Config::Hulk::COUNTRY_WHITE_LIST_TYPE : $Cpanel::Config::Hulk::COUNTRY_BLACK_LIST_TYPE;

                    $dbh->do( "delete from ip_lists where TYPE=?", {}, $key );
                    foreach my $range ( @{ $list_ranges{$list_type} } ) {
                        $insert_q->execute( $range->[0], $range->[1], $key, $range->[2] );
                    }
                }
                $insert_q->finish();
                $dbh->do( qq{INSERT OR REPLACE INTO config_track (ENTRY,VALUE) VALUES('last_update_country_ips_time',?);}, {}, $conf_mtime );
                $dbh->do("COMMIT TRANSACTION;");
                require Cpanel::Hulk::Cache::IpLists;
                Cpanel::Hulk::Cache::IpLists->new->expire_all();

            }
        };
        if ($@) {
            my $ex = $@;
            require Cpanel::Exception;
            $logger->warn( 'The system encountered an error while trying to update country ips: ' . Cpanel::Exception::get_string($ex) );
            return 0;
        }
        return 1;
    }
}

{

    package Cpanel::TaskProcessors::cPHulkTasks::BlockBruteForce;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub deferral_tags {
        my ($self) = @_;
        return qw/block_brute_force/;
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        Cpanel::LoadModule::load_perl_module('Cpanel::Hulkd::QueuedTasks::BlockBruteForce::Harvester');
        Cpanel::Hulkd::QueuedTasks::BlockBruteForce::Harvester->harvest(
            sub {
                return $self->_block_brute_force( shift, $logger );
            }
        );
        return 1;
    }

    sub _block_brute_force {
        my ( $self, $data_hr, $logger ) = @_;

        if ( exists $data_hr->{'commands'} ) {
            require Cpanel::SafeRun::Object;

            my ( $prog, @args ) = @{ $data_hr->{'commands'} };

            # case CPANEL-29184 adds a 15 second timeout so these don't block
            # the queue forver
            my $run = Cpanel::SafeRun::Object->new(
                program      => $prog,
                args         => \@args,
                timeout      => 15,
                read_timeout => 15
            );

            if ( $run->CHILD_ERROR() ) {
                $logger->warn( "Error while running _block_brute_force command: [(@{$data_hr->{'commands'}})]: " . join( q< >, map { $run->$_() // () } qw( autopsy stdout stderr ) ) );
            }
            elsif ( $run->stdout() || $run->stderr() ) {
                $logger->warn( "Output while running _block_brute_force command: [(@{$data_hr->{'commands'}})]: " . join( q< >, map { $run->$_() // () } qw( stdout stderr ) ) );
            }

        }

        if ( $data_hr->{'block_with_firewall'} ) {
            require Cpanel::XTables::TempBan;
            eval {
                my $iptables_obj = Cpanel::XTables::TempBan->new( 'chain' => 'cphulk', 'ipversion' => $data_hr->{'ip_version'} );

                if ( !$iptables_obj->can_temp_ban() ) {
                    $logger->warn("iptables 1.4 or later (on a non-virtuozzo system) is required to create temporary bans.");
                    return 0;
                }
                my $chain_exists = $iptables_obj->chain_exists() || 0;
                $iptables_obj->init_chain() if !$chain_exists;
                $iptables_obj->check_chain_position();
                my $chain_attached = $iptables_obj->is_chain_attached('INPUT');
                $iptables_obj->attach_chain('INPUT') if !$iptables_obj->is_chain_attached('INPUT');
                $iptables_obj->add_temp_block( $data_hr->{'remote_ip'}, $data_hr->{'exptime'} );
            };
            if ($@) {
                my $err = $@;
                $logger->warn("Error while attempt to block IP: $data_hr->{'remote_ip'}: $err");
            }
        }

        return 1;
    }
}

sub to_register {
    return (
        [ 'purge_old_logins'      => Cpanel::TaskProcessors::cPHulkTasks::KnownNetblocks::PurgeOldLogins->new() ],
        [ 'add_known_ip_for_user' => Cpanel::TaskProcessors::cPHulkTasks::KnownNetblocks::AddIPForUser->new() ],
        [ 'notify_login'          => Cpanel::TaskProcessors::cPHulkTasks::KnownNetblocks::NotifyLogin->new() ],
        [ 'notify_brute'          => Cpanel::TaskProcessors::cPHulkTasks::KnownNetblocks::NotifyBrute->new() ],
        [ 'update_country_ips'    => Cpanel::TaskProcessors::cPHulkTasks::KnownNetblocks::UpdateCountryIps->new() ],
        [ 'block_brute_force'     => Cpanel::TaskProcessors::cPHulkTasks::BlockBruteForce->new() ],
    );
}

1;

__END__

=head1 NAME

Cpanel::TaskProcessors::cPHulkTasks - Task processor for handling certain cPHulk tasks.

=head1 SYNOPSIS

    # processor side
    use Cpanel::TaskQueue;
    my $queue = Cpanel::TaskQueue->new( { name => 'servers', cache_dir => '/var/cpanel/taskqueue' } );
    Cpanel::TaskQueue->register_task_processor( 'cPHulkTasks', Cpanel::TaskProcessors::cPHulkTasks->new() );

    # client/queuing side
    use Cpanel::ServerTasks;
    Cpanel::ServerTasks::queue_task(
        ['cPHulkTasks'],
        join " ", ( 'notify_login', Cpanel::JSON::Dump( $self->{'request'} ), Cpanel::JSON::Dump( \%OPTS ) )
    );

=head1 DESCRIPTION

A task processor that handles various tasks for cPHulk. Tasks that either take
time to process, or can be done out-of-band with the cPHulk process.

=head1 TASKS

=head2 to_register

Register the following tasks:

=over 4

=item update_country_ips

    use Cpanel::ServerTasks;
    Cpanel::ServerTasks::queue_task(
        ['cPHulkTasks'], 'update_country_ips'
    );

This event takes no arguments.

Update the ip ranges for blacklisted and whitelisted country codes into the
C<ip_lists> table of the cPHulk DB.

=item purge_old_logins

    use Cpanel::ServerTasks;
    Cpanel::ServerTasks::queue_task(
        ['cPHulkTasks'], 'purge_old_logins'
    );

This event takes no arguments.

Purge expired entries from the C<known_netblocks> table of the cPHulk DB.

=item add_known_ip_for_user

    use Cpanel::ServerTasks;
    Cpanel::ServerTasks::queue_task(
        ['cPHulkTasks'], 'add_known_ip_for_user ' . Cpanel::JSON::Dump( $self->{'request'} )
    );

This event takes one argument. The JSON string containing details about the cPHulk request.

Performs a WHOIS lookup on the connecting IP address, and if successful, adds the net range in the reply to the DB.
If the WHOIS lookup fails, then it simply adds the single IP address to the DB.

=item notify_login

    use Cpanel::ServerTasks;
    Cpanel::ServerTasks::queue_task(
        ['cPHulkTasks'],
        join " ", ( 'notify_login', Cpanel::JSON::Dump( $self->{'request'} ), Cpanel::JSON::Dump( \%OPTS ) )
    );

This event takes two arguments.
The first argument must be the JSON string containing details about the cPHulk request.
The second argument must be the JSON string containing details about the notification configuration.

Based on the configuration, sends a notification to the user about the login event.

=item notify_brute

    use Cpanel::ServerTasks;
    Cpanel::ServerTasks::queue_task(
        ['cPHulkTasks'],
        join " ", ( 'notify_brute', Cpanel::JSON::Dump( $self->{'request'} ), Cpanel::JSON::Dump( \%OPTS ) )
    );

This event takes two arguments.
The first argument must be the JSON string containing details about the cPHulk request.
The second argument must be the JSON string containing details about the notification configuration.

Based on the configuration, sends a notification to the server administrator about the brute forced attempt.

=back
