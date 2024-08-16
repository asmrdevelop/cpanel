package Cpanel::Userdomains::CORE;

# cpanel - Cpanel/Userdomains/CORE.pm                Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::HiRes                  ();
use Cpanel::Autodie                ();
use Cpanel::Chdir                  ();
use Cpanel::ConfigFiles            ();
use Cpanel::Sys::Hostname::Tiny    ();
use Cpanel::InternalDBS            ();
use Cpanel::FileUtils::TouchFile   ();
use Cpanel::FileUtils::Dir         ();
use Cpanel::Config::LoadCpConf     ();
use Cpanel::EmailLimits            ();
use Cpanel::Finally                ();
use Cpanel::Validate::Username     ();
use Cpanel::Signal                 ();
use Cpanel::Signal::Defer          ();
use Cpanel::SMTP::ReverseDNSHELO   ();
use Cpanel::PwCache::Map           ();
use Cpanel::PwCache                ();
use Cpanel::FileUtils::Access      ();
use Cpanel::Config::LoadCpUserFile ();
use Cpanel::Sys::Chattr            ();
use Cpanel::LoginDefs              ();
use Cpanel::FileUtils::Write       ();
use Cpanel::Transaction::File::Raw ();
use Cpanel::AdminBin::Serializer   ();    # PPI USE OK - Needed to optimize loadcpconf
use Cpanel::JSON                   ();    # PPI USE OK - Needed to optimize loadcpconf
use Cpanel::ConfigFiles            ();

my $CPUSER_DATA_CHECK_TIME = 300;
our $ONE_DAY = 86400;

use constant SINGLE_HASH  => 0;
use constant HASH         => 3;
use constant REVERSE_HASH => 4;

my %READDB_TYPES = (
    'SINGLE_HASH'  => 0,
    'HASH'         => 3,
    'REVERSE_HASH' => 4
);

sub new {
    my ( $class, %args ) = @_;

    my $self = {};

    $self->{'force'}       = $args{'force'}   || 0;
    $self->{'verbose'}     = $args{'verbose'} || 0;
    $self->{'internaldbs'} = Cpanel::InternalDBS::get_all_dbs();
    $self->{'gid_cache'}   = {};

    return bless $self, $class;
}

sub _get_cached_user_gid {
    my ( $self, $user ) = @_;
    return ( $self->{'gid_cache'}{$user} ||= ( Cpanel::PwCache::getpwnam_noshadow($user) )[3] );
}

sub update {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ( $self, %args ) = @_;

    die "Must call new() before update()" unless ref $self;

    $self->{'force'}   = $args{'force'}   if ( exists $args{'force'} );
    $self->{'verbose'} = $args{'verbose'} if ( exists $args{'verbose'} );

    my $start_update_time = Cpanel::HiRes::time();

    $self->{'commit_list'}  = {};
    $self->{'dbmtimes'}     = {};
    $self->{'transactions'} = {};
    $self->{'cache_dbs'}    = {};
    $self->{'hostname'}     = Cpanel::Sys::Hostname::Tiny::gethostname();

    my $email_limits = $self->_get_email_limits();

    $self->_create_eximrejects_if_missing();
    $self->_create_localdomains_if_missing();

    my $needs_update       = ( $self->{'force'} ? 1 : 0 );
    my $per_domain_mailips = per_domain_mailips_is_enabled();
    my $use_rdns_for_helo  = use_rdns_for_helo_is_enabled();
    my $custom_mail_helo   = _custom_mail_helo();
    my $custom_mail_ips    = _custom_mail_ips();

    my $oldest_db_mtime;

    # This must be sorted properly or we will deadlock.
    foreach my $dbref ( sort { $a->{'file'} cmp $b->{'file'} } ( @{ $self->{'internaldbs'} } ) ) {
        if ( $dbref->{'cache'} ) {
            $self->_create_transaction($dbref);
            my $mtime = $self->{'transactions'}{ $dbref->{'file'} }->get_mtime();
            if ( !defined $oldest_db_mtime || $mtime < $oldest_db_mtime ) {
                $oldest_db_mtime = $mtime;
            }
        }
        else {
            $self->_ensure_perms_and_ownership($dbref);
        }
    }

    my $USER_BWLIMITS     = $self->{'cache_dbs'}{'BWLIMIT'}             || {};
    my $USER_PLANS        = $self->{'cache_dbs'}{'PLANS'}               || {};
    my $DBOWNERS          = $self->{'cache_dbs'}->{'DBOWNERS'}          || {};
    my $TRUE_USER_OWNERS  = $self->{'cache_dbs'}->{'OWNER'}             || {};
    my $DEMO              = $self->{'cache_dbs'}->{'DEMOUIDS'}          || {};
    my $MAIL_HELO         = $self->{'cache_dbs'}->{'MAIL_HELO'}         || {};
    my $NOCGI             = $self->{'cache_dbs'}->{'NOCGI'}             || {};
    my $EMAIL_SEND_LIMITS = $self->{'cache_dbs'}->{'EMAIL_SEND_LIMITS'} || {};
    my $MAILBOX_FORMATS   = $self->{'cache_dbs'}->{'MAILBOX_FORMATS'}   || {};
    my $DOMAIN_USERS      = $self->{'cache_dbs'}->{'DOMAINS'}           || {};
    my $TRUE_USER_DOMAINS = $self->{'cache_dbs'}->{'DOMAIN'}            || {};
    my $USER_IPS          = $self->{'cache_dbs'}->{'USER_IPS'}          || {};

    my $USERS_DOMAINS;

    my ( $size, $userfilemtime, $cpuserfile, @DOMAINS );
    my $this_version_mtime  = ( Cpanel::HiRes::stat(__FILE__) )[9];
    my $cpanel_config_mtime = ( Cpanel::HiRes::stat($Cpanel::ConfigFiles::cpanel_config_file) )[9];
    #
    # If the oldest_db_mtime is older then now  = ok otherwise we have a timewarp
    # If the mtime of updateuserdomains is older then the oldest db = ok otherwise updateuserdomains has been updated and we do a full rebuild
    #
    my $database_is_valid = ( $oldest_db_mtime <= Cpanel::HiRes::time() && $cpanel_config_mtime < $oldest_db_mtime && $this_version_mtime < $oldest_db_mtime ) ? 1 : 0;

    print "updateuserdomains database validity : $database_is_valid\n" if $self->{'verbose'};

    my %RESERVED_USERNAMES = map { $_ => 1 } ( 'cpanel', Cpanel::Validate::Username::list_reserved_usernames() );

    my $need_direct_lookup = !$database_is_valid || $self->{'force'};
    my $uid_min            = Cpanel::LoginDefs::get_uid_min();

    # This directory might be absent on fresh installs, and that's okay.
    my $nodes              = -d '/var/cpanel/users' ? Cpanel::FileUtils::Dir::get_directory_nodes('/var/cpanel/users') : [];
    my %cpanel_users_files = map { $_ => 1 } @$nodes;

    # Cleanup step to eliminate references to deleted accounts.
    my $user_uid_map_ref = Cpanel::PwCache::Map::get_name_id_map('passwd');
    my $is_valid_user    = $user_uid_map_ref;

    if ( delete $cpanel_users_files{'system'} ) {

        # Special case: system domains need to be added even though system is not considered a valid cPanel account.
        #
        # We need to store unowned domains in /etc/userdomains in order to allow dnsadmin
        # to be able to make changes to these domains.  For more information please see
        # FB-72685
        #
        $cpanel_users_files{'nobody'} = 1;
        $user_uid_map_ref->{'nobody'} = $uid_min;
        delete $RESERVED_USERNAMES{'nobody'};    # we want to load VCU/system
        $TRUE_USER_DOMAINS->{'nobody'} = '*';
    }

    #
    # Avoid the path lookup for /var/cpanel/users/$user
    #
    {
        my $chdir = Cpanel::Chdir->new('/var/cpanel/users');
        my $relative_path;
        foreach my $user (
            grep {
                $cpanel_users_files{$_}               &&    #
                  !$RESERVED_USERNAMES{$_}            &&    #
                  $user_uid_map_ref->{$_} >= $uid_min &&    #
                  index( $_, 'cptkt' ) != 0                 #
            } keys %$user_uid_map_ref
        ) {
            $relative_path = $user eq 'nobody' ? 'system' : $user;
            ( $size, $userfilemtime ) = ( Cpanel::HiRes::lstat($relative_path) )[ 7, 9 ];
            next if !$size;

            # user file has to be at least an hour better
            # and timewarm safe
            # and be in the db
            if (   $need_direct_lookup
                || ( $userfilemtime + $CPUSER_DATA_CHECK_TIME ) > $oldest_db_mtime
                || !$DBOWNERS->{$user}
                || !$TRUE_USER_DOMAINS->{$user}
                || !$DOMAIN_USERS->{ $TRUE_USER_DOMAINS->{$user} } ) {

                $USERS_DOMAINS ||= _map_users_domains_from_domain_users($DOMAIN_USERS);
                delete @{$DOMAIN_USERS}{ @{ $USERS_DOMAINS->{$user} } } if ref $USERS_DOMAINS->{$user};

                $needs_update = 1;
                if ( $self->{'verbose'} ) { print "$user has missing or newer data, forcing full load of their user data. !(( $userfilemtime +  $CPUSER_DATA_CHECK_TIME ) > $oldest_db_mtime)\n"; }
                $cpuserfile = Cpanel::Config::LoadCpUserFile::load($relative_path);
                if ( !$cpuserfile || ( !$cpuserfile->{'DOMAIN'} && $user ne 'nobody' ) ) {

                    # The user was deleted between the time we stat the file above
                    # and when we call load on it
                    next;
                }
                my $cpuser = $cpuserfile->{'DBOWNER'} || $cpuserfile->{'USER'};
                $DBOWNERS->{$user}          = $cpuser if $cpuser;
                @DOMAINS                    = ( ref $cpuserfile->{'DOMAINS'} eq 'ARRAY' ? @{ $cpuserfile->{'DOMAINS'} } : () );
                $TRUE_USER_DOMAINS->{$user} = $cpuserfile->{'DOMAIN'};
                foreach my $domain ( $cpuserfile->{'DOMAIN'}, @DOMAINS ) {
                    #
                    # We used to check to see if the domain is valid, however that is
                    # done when the account/domain is created.
                    #
                    # In this case we really only care if the domain name contains
                    # a record separator of " ", ":" or "\n" so we just check to make
                    # sure it only contains characters we expect in a domain name in
                    # order to protect the system against manual edits which may break
                    # the userdomains database/cache.
                    #
                    if ( !$domain || $domain =~ tr{_*.a-z0-9-}{}c ) {
                        if ( $user ne 'nobody' ) {
                            warn "Invalid domain “$domain” assigned to the user “$user”.";
                        }
                        next;    # do not include invalid domain
                    }
                    elsif ( $domain eq $self->{'hostname'} ) {
                        _notify_hostname_owned_by_user( $self->{'hostname'}, $user );
                        next;
                    }
                    elsif ( !exists $DOMAIN_USERS->{$domain} ) {
                        $DOMAIN_USERS->{$domain} = $user;
                    }
                    elsif ( $DOMAIN_USERS->{$domain} ne $user && $is_valid_user->{ $DOMAIN_USERS->{$domain} } ) {
                        if ( $DOMAIN_USERS->{$domain} eq 'nobody' ) {

                            # case CPANEL-10711: If the domain is in  /var/cpanel/users/system and it also belongs
                            # to a user, the user always wins
                            $DOMAIN_USERS->{$domain} = $user;
                            _logger_warn( $self->{'verbose'}, "domain conflict: $domain: /var/cpanel/users/system contains a " . ( ( $domain eq $cpuserfile->{'DOMAIN'} ) ? 'MAIN ' : '' ) . "domain already owned by $DOMAIN_USERS->{$domain}" );
                        }
                        else {
                            # No need to warn about a domain conflict for a user that is about
                            # to be removed below as long as $needs_update is set (which is always is at this point)
                            _logger_warn( $self->{'verbose'}, "domain conflict: $domain: /var/cpanel/users/${user} contains a " . ( ( $domain eq $cpuserfile->{'DOMAIN'} ) ? 'MAIN ' : '' ) . "domain already owned by $DOMAIN_USERS->{$domain}" );
                            next;
                        }
                    }

                    if ( !( $EMAIL_SEND_LIMITS->{$domain} = $email_limits->get_email_send_limit_key( $user, $domain, $cpuserfile ) ) ) {
                        delete $EMAIL_SEND_LIMITS->{$domain};    # In this case there is no account level and an empty entry means "use global default"
                    }
                }
                if ( $user ne 'nobody' ) {
                    $MAILBOX_FORMATS->{$user}  = ( $cpuserfile->{'MAILBOX_FORMAT'} || 'maildir' );
                    $USER_PLANS->{$user}       = ( $cpuserfile->{'PLAN'}           || 'default' );
                    $USER_BWLIMITS->{$user}    = ( $cpuserfile->{'BWLIMIT'}        || '0' );
                    $TRUE_USER_OWNERS->{$user} = ( $cpuserfile->{'OWNER'}          || 'root' );
                    if ( $cpuserfile->{'IP'} ) {

                        # In the distant past we did not set this value so its possible there
                        # are still a few user files in the wild that are missing this value
                        # This not a problem since it will fallback to the userdata
                        # cache and in the event of an IP change it will be populated.
                        $USER_IPS->{$user} = $cpuserfile->{'IP'};
                    }
                    if ( $cpuserfile->{'DEMO'} && $cpuserfile->{'DEMO'} eq '1' ) {
                        $DEMO->{$user} = $user_uid_map_ref->{$user};
                    }
                    else {
                        delete $DEMO->{$user};
                    }
                    if ( exists $cpuserfile->{'HASCGI'} && $cpuserfile->{'HASCGI'} eq '0' ) {
                        $NOCGI->{$user} = undef;
                    }
                    else {
                        delete $NOCGI->{$user};
                    }

                    if ( !$cpuserfile->{'DOMAIN'} ) {
                        _logger_warn( $self->{'verbose'}, "user $user: missing DNS= line in /var/cpanel/users/${user}" );
                    }
                }
            }
        }
    }

    delete $TRUE_USER_DOMAINS->{'nobody'};    # always set to *

    $needs_update = 1 if ( ( $EMAIL_SEND_LIMITS->{'*'} // '' ) ne $email_limits->{'email_send_limit_default_key'} );
    delete $EMAIL_SEND_LIMITS->{'*'};         # needs to be deleted because we will manually write this in later

    $needs_update = 1
      if delete @{$TRUE_USER_DOMAINS}{ grep { !$_ || !$is_valid_user->{$_} } keys %$TRUE_USER_DOMAINS };

    $needs_update = 1
      if delete @{$DOMAIN_USERS}{ grep { !$_ || !$is_valid_user->{ $DOMAIN_USERS->{$_} } } keys %$DOMAIN_USERS };

    $needs_update = 1
      if delete @{$TRUE_USER_OWNERS}{ grep { !$is_valid_user->{$_} } keys %$TRUE_USER_OWNERS };

    $needs_update = 1
      if delete @{$TRUE_USER_OWNERS}{ grep { !$is_valid_user->{$_} } values %$TRUE_USER_OWNERS };

    $needs_update = 1
      if delete @{$MAILBOX_FORMATS}{ grep { !$is_valid_user->{$_} } keys %$MAILBOX_FORMATS };

    $needs_update = 1
      if delete @{$USER_PLANS}{ grep { !$is_valid_user->{$_} } keys %$USER_PLANS };

    $needs_update = 1
      if delete @{$DBOWNERS}{ grep { !$is_valid_user->{$_} } keys %$DBOWNERS };

    $needs_update = 1
      if delete @{$USER_BWLIMITS}{ grep { !$is_valid_user->{$_} } keys %$USER_BWLIMITS };

    $needs_update = 1
      if delete @{$USER_IPS}{ grep { !$is_valid_user->{$_} } keys %$USER_IPS };

    if ( !$custom_mail_helo ) {
        if ( delete @{$MAIL_HELO}{ grep { !$_ || !$DOMAIN_USERS->{$_} || !$is_valid_user->{ $DOMAIN_USERS->{$_} } } keys %$MAIL_HELO } ) {
            $needs_update = 1;
        }
    }

    my $hostname = $self->{'hostname'};
    if ( exists $DOMAIN_USERS->{$hostname} ) {
        _notify_hostname_owned_by_user( $hostname, $DOMAIN_USERS->{$hostname} );
        delete $DOMAIN_USERS->{$hostname};
        $needs_update = 1;
    }

    $needs_update = 1
      if delete @{$EMAIL_SEND_LIMITS}{ grep { !$DOMAIN_USERS->{$_} } keys %$EMAIL_SEND_LIMITS };

    if ($needs_update) {
        print "Updating databases.\n" if $self->{'verbose'};
        require Cpanel::Config::ReverseDnsCache;
        my $ip_to_reversedns_map = $use_rdns_for_helo ? Cpanel::Config::ReverseDnsCache::get_ip_to_reversedns_map() : {};
        require Cpanel::DIp::MainIP;
        my $main_shared_ip = Cpanel::DIp::MainIP::getmainsharedip();
        my $main_server_ip = Cpanel::DIp::MainIP::getmainserverip();
        if ($per_domain_mailips) {

            # ** This shares much of the same logic as Cpanel::DIp::Update does
            # ** it may be better to update these when we do the DIp update in
            # ** the future.
            require Cpanel::Ips::Fetch;
            require Cpanel::DIp::IsDedicated;
            require Cpanel::Reseller;

            # case CPANEL-20348:
            # We use Cpanel::DIp::MainIP::getmainsharedip() here since
            # this is what Whostmgr::Accounts::Create uses as well
            #
            # getmainsharedip/$main_shared_ip is described as
            # "Shared Virtual Host IPv4 Address" in Whostmgr::TweakSettings::Basic
            #
            # getmainserverip/$main_server_ip is the default ip address that
            # the server will make connections from if an outbound ip is not
            # specified
            my @mailips;
            my @mailhelo;

            my $current_ips_ref = Cpanel::Ips::Fetch::fetchipslist();
            $self->{'userdata'} = undef;

            # Each IP may only have one helo or it will be blacklisted
            # We use a hash to ensure there are no duplicates
            # as there can be only one.
            my $IP_HELO_MAP_hr = $self->_get_shared_ip_to_maindomain_map( $main_shared_ip, $TRUE_USER_DOMAINS );
            my %_dedicated_ip_cache;

            # Next make sure $USER_IPS for each user is filled in
            # and set the helo for any dedicated ips in %IP_HELO_MAP.
            foreach my $user ( grep { $_ ne 'nobody' } keys %$TRUE_USER_DOMAINS ) {
                my $main_domain = $TRUE_USER_DOMAINS->{$user};
                my $ip          = ( $USER_IPS->{$user} ||= $self->_get_ip_for_user( $user, $main_domain ) );
                if ( $_dedicated_ip_cache{$ip} //= Cpanel::DIp::IsDedicated::isdedicatedip($ip) ) {
                    $IP_HELO_MAP_hr->{$ip} = $main_domain;
                }
            }

            @{$IP_HELO_MAP_hr}{ keys %$ip_to_reversedns_map } = values %$ip_to_reversedns_map;

            foreach my $domain ( keys %$DOMAIN_USERS ) {
                my $ip = $USER_IPS->{ $DOMAIN_USERS->{$domain} };
                next if ( !$ip || $ip eq $main_shared_ip || !exists $current_ips_ref->{$ip} );
                push @mailips, [ $domain => $ip ];
                if ( $IP_HELO_MAP_hr->{$ip} ) {
                    push @mailhelo, [ $domain => $IP_HELO_MAP_hr->{$ip} ];
                }
            }

            # case CPANEL-20348:
            # We only add the default * if there are any entries
            # or the main server ip is not the same as the main
            # shared ip (see above for details)
            if ( @mailips || $main_shared_ip ne $main_server_ip ) {
                push @mailips, [ '*' => $main_shared_ip ];
            }

            if ( $ip_to_reversedns_map->{$main_shared_ip} ) {
                push @mailhelo, [ '*' => $ip_to_reversedns_map->{$main_shared_ip} ];
            }

            for my $ar ( \@mailips, \@mailhelo ) {
                @$ar = map { "$_->[0]: $_->[1]\n" } @$ar;
            }

            $self->_stage_data( 'mailips',  \@mailips )  if !$custom_mail_ips;
            $self->_stage_data( 'mailhelo', \@mailhelo ) if !$custom_mail_helo;
        }
        else {
            # If per_domain_mailips is disabled and custom is not, clear /etc/mail*
            $self->_stage_data( 'mailips', [] ) if !$custom_mail_ips;

            # see CPANEL-31761: use the mail server ip (which should be the ip we make connections from for rdns helo when per domain mail ips is disabled)
            $self->_stage_data( 'mailhelo', [ $ip_to_reversedns_map->{$main_server_ip} ? "*: $ip_to_reversedns_map->{$main_server_ip}" : "" ] ) if !$custom_mail_helo;
        }

        $DOMAIN_USERS->{'*'} = 'nobody';
        $self->_stage_data( 'userdomains',     $DOMAIN_USERS );
        $self->_stage_data( 'userbwlimits',    $USER_BWLIMITS, 'userbwlimits' );
        $self->_stage_data( 'userips',         $USER_IPS,      'userips' );
        $self->_stage_data( 'dbowners',        $DBOWNERS,      'dbowners' );
        $self->_stage_data( 'userplans',       $USER_PLANS,    'userplans' );
        $self->_stage_data( 'trueuserowners',  $TRUE_USER_OWNERS );
        $self->_stage_data( 'mailbox_formats', $MAILBOX_FORMATS, 'mailbox_formats' );
        $self->_stage_data( 'trueuserdomains', { reverse %$TRUE_USER_DOMAINS } );
        $self->_stage_data( 'domainusers',     $TRUE_USER_DOMAINS, );
        $self->_stage_data( 'demousers',       [ map { "$_\n" } sort keys %$DEMO ], );
        $self->_stage_data( 'nocgiusers',      [ map { "$_\n" } sort keys %$NOCGI ], );
        $self->_stage_data(
            'email_send_limits',
            [
                "#version 1.0\n#format DOMAIN: MAX_EMAIL_PER_HOUR,MAX_DEFER_FAIL_PERCENTAGE,MIN_DEFER_FAIL_TO_TRIGGER_PROTECTION\n",
                ( map { "$_: $EMAIL_SEND_LIMITS->{$_}\n" } sort keys %$EMAIL_SEND_LIMITS ),
                "*: $email_limits->{'email_send_limit_default_key'}\n",
            ],
        );
        $self->_stage_data( 'demouids', { reverse %$DEMO } );
        $self->_stage_data(
            'demodomains',
            [
                map       { "$_\n" }
                sort grep { $DEMO->{ $DOMAIN_USERS->{$_} } } keys %$DOMAIN_USERS
            ],
        );

    }
    else {
        print "Not updating databases.\n" if $self->{'verbose'};
    }

    {
        my $defer;
        my $undefer;
        if ( scalar keys %{ $self->{'commit_list'} } ) {
            $defer = Cpanel::Signal::Defer->new(
                defer => {
                    signals => Cpanel::Signal::Defer::NORMALLY_DEFERRED_SIGNALS(),
                    context => "writing Userdomains::CORE to disk",
                }
            );
            $undefer = Cpanel::Finally->new(
                sub {
                    $defer->restore_original_signal_handlers();
                    undef $defer;
                }
            );
        }

        foreach my $db ( sort keys %{ $self->{'transactions'} } ) {
            if ( $self->{'commit_list'}{$db} ) {
                $self->{'transactions'}{$db}->save_or_die( 'signals_already_deferred' => 1 );
            }

            my $fh = $self->{'transactions'}{$db}->get_fh();

            Cpanel::Sys::Chattr::set_attribute( $fh, 'NOATIME' );
            Cpanel::HiRes::futime( $start_update_time, $start_update_time, $fh );

            $self->{'transactions'}{$db}->close_or_die();
            delete $self->{'transactions'}{$db};
        }

        delete $self->{'cache_dbs'};

        if ($defer) {
            $defer->restore_original_signal_handlers();
            $undefer->skip();
        }
    }

    Cpanel::Signal::send_hup('tailwatchd') if $needs_update;

    if ( -x '/usr/local/cpanel/scripts/postupdateuserdomains' ) {
        system '/usr/local/cpanel/scripts/postupdateuserdomains',
          ( $self->{'force'} ? ('--force') : () ), ( $self->{'verbose'} ? ('--verbose') : () );
    }

    return 1;
}

sub _map_users_domains_from_domain_users {
    my ($DOMAIN_USERS) = @_;
    my %USERS_DOMAINS;
    push @{ $USERS_DOMAINS{ $DOMAIN_USERS->{$_} } }, $_ for keys %${DOMAIN_USERS};
    return \%USERS_DOMAINS;
}

# Actually creates the file...
sub _ensure_perms_and_ownership {
    my ( $self, $dbref ) = @_;
    Cpanel::FileUtils::TouchFile::touchfile( $dbref->{'path'} ) if !-e $dbref->{'path'};
    Cpanel::FileUtils::Access::ensure_mode_and_owner( $dbref->{'path'}, $dbref->{'perms'}, 0, $self->_get_cached_user_gid( $dbref->{'group'} ) );
    return 1;
}

sub _create_transaction {
    my ( $self, $dbref ) = @_;

    # We only manage db caches here
    my $key  = $dbref->{'key'};
    my $file = $dbref->{'file'};

    $self->{'transactions'}{$file} = Cpanel::Transaction::File::Raw->new(
        'path'        => $dbref->{'path'},
        'permissions' => $dbref->{'perms'},
        'ownership'   => [ 0, $self->_get_cached_user_gid( $dbref->{'group'} ) ]
    );

    if ( $key && !$self->{'force'} ) {
        my $order = $READDB_TYPES{ $dbref->{'order'} };

        if ( !defined $order ) {
            die "$file is missing the 'order' key";
        }

        $self->_readdb( $self->{'transactions'}{$file}, $key, $order ) unless $self->{'force'};
    }
    return 1;
}

sub _create_eximrejects_if_missing {
    my ($self) = @_;

    if ( !-e '/etc/eximrejects' ) {
        my $msg = <<"REJECTMSG";
host_accept_relay:      Host \$sender_fullhost is not permitted|
                        to relay through \$primary_hostname.|
                        Perhaps you have not logged into the pop/imap server in the last 30 minutes.|
                        You may also have been rejected because your ip address|
                        does not have a reverse DNS entry.
REJECTMSG
        Cpanel::FileUtils::Write::overwrite( '/etc/eximrejects', $msg, 0644 );
    }
    return;
}

# Not like _create_eximrejects_if_missing
# Does not actually "create localdomains if missing".
# Only adds to the file IF file is of size 0.
sub _create_localdomains_if_missing {
    my ($self) = @_;
    my $hostname = $self->{'hostname'};

    my $last_line            = '';
    my $needs_hostname_added = 1;

    if ( -e $Cpanel::ConfigFiles::LOCALDOMAINS_FILE ) {
        if ( open( my $local_domains_fh, '<', $Cpanel::ConfigFiles::LOCALDOMAINS_FILE ) ) {
            while ( my $domain = readline($local_domains_fh) ) {
                $last_line = $domain;
                chomp($domain);
                if ( $needs_hostname_added && $domain eq $hostname ) {
                    $needs_hostname_added = 0;
                }
            }
        }
    }

    if ($needs_hostname_added) {
        if ( open( my $local_domains_fh, '>>', $Cpanel::ConfigFiles::LOCALDOMAINS_FILE ) ) {
            print {$local_domains_fh} "\n" if ( $last_line !~ /\n$/ );
            print {$local_domains_fh} $hostname . "\n";
        }
    }
    return;
}

sub _notify_hostname_owned_by_user {
    my ( $hostname, $user ) = @_;
    require Cpanel::Notify;
    Cpanel::Notify::notification_class(
        'class'            => 'Check::HostnameOwnedByUser',
        'application'      => 'updateuserdomains',
        'interval'         => $ONE_DAY,
        'status'           => "conflict",
        'constructor_args' => [
            'origin' => 'updateuserdomains',
            'user'   => $user,
        ],
    );
    print "== WORKAROUND ENABLED ==\n";
    print "Serious Problem -- This should never happen!!\n";
    print "The hostname ($hostname) is owned by the user $user\n";
    print "== WORKAROUND ENABLED ==\n";
    return 1;
}

sub _stage_data {
    my ( $self, $db, $data, $header ) = @_;

    my $trans = $self->{'transactions'}{$db};

    # If we didn't want to write this database (say, /etc/mailips is custom),
    # then do nothing.
    return 0 unless $trans;

    # case CPANEL-9254:
    # Do not sort arrays here as we expect them to be presorted
    my $new = join(
        '',
        ( $header              ? "#$header v1\n" : '' ),
        ( ref $data eq 'ARRAY' ? @$data          : ( map { "$_: $data->{$_}\n" } sort keys %$data ) )
    );

    if ( ${ $trans->get_data() } ne $new ) {
        $self->{'commit_list'}{$db} = 1;
        $trans->set_data( \$new );
    }

    return 0;
}

sub _get_email_limits {
    my ($self) = @_;
    return Cpanel::EmailLimits->new( 'cpconf' => scalar Cpanel::Config::LoadCpConf::loadcpconf_not_copy() );
}

sub _readdb {
    my ( $self, $trans, $keyname, $order ) = @_;

    my $dataref = $trans->get_data();
    if ( $order == HASH ) {
        %{ $self->{'cache_dbs'}{$keyname} } = map { index( $_, '#' ) == -1 ? ( split( m{: }, $_, 2 ) )[ 0, 1 ] : () } ( split( m{\n}, $$dataref ) );    #field0 = field1
    }
    elsif ( $order == REVERSE_HASH ) {
        %{ $self->{'cache_dbs'}{$keyname} } = map { index( $_, '#' ) == -1 ? ( split( m{: }, $_, 2 ) )[ 1, 0 ] : () } ( split( m{\n}, $$dataref ) );    #field1 = field0
    }
    else {                                                                                                                                              # $READDB_TYPES{'SINGLE_HASH'}
        %{ $self->{'cache_dbs'}{$keyname} } = map { $_ => 1 } ( split( m{\n}, $$dataref ) );                                                            #field0 = 1
        delete @{ $self->{'cache_dbs'}{$keyname} }{ '', grep { index( $_, '#' ) == -1 } keys %{ $self->{'cache_dbs'}{$keyname} } };
    }

    return 1;
}

sub _logger_warn {
    my ( $verbose, $message ) = @_;
    require Cpanel::Logger;
    return Cpanel::Logger::logger(
        {
            'message'   => $message,
            'level'     => 'warn',
            'backtrace' => 0,
            'service'   => 'updateuserdomains',
            'output'    => $verbose,
        }
    );
}

sub _custom_mail_ips {
    if ( !-e '/var/cpanel/custom_mailips' || !-e $Cpanel::ConfigFiles::MAILIPS_FILE ) {
        return 0;
    }
    return 1;
}

sub _custom_mail_helo {
    if ( !-e '/var/cpanel/custom_mailhelo' || !-e $Cpanel::ConfigFiles::MAILHELO_FILE ) {
        return 0;
    }
    return 1;
}

sub use_rdns_for_helo_is_enabled {
    return Cpanel::SMTP::ReverseDNSHELO->is_on();
}

sub per_domain_mailips_is_enabled {
    return Cpanel::Autodie::exists('/var/cpanel/per_domain_mailips') ? 1 : 0;
}

sub _get_ip_for_user {
    my ( $self, $user, $main_domain ) = @_;

    # If the userdata cache is not built yet because the domain
    # was just added, we need to fallback to the cpanel user data
    if ( !$self->{'userdata'} ) {
        require Cpanel::Config::userdata::Cache;
        $self->{'userdata'} = Cpanel::Config::userdata::Cache::load_cache();
    }

    my $ip = $self->{'userdata'}->{$main_domain}->[5];
    if ( length $ip ) {
        $ip =~ s/:\d+$// if index( $ip, ':' ) > -1;    # Strip off port number
        return $ip;
    }

    my $cpuser_ref = Cpanel::Config::LoadCpUserFile::load($user);

    return if !$cpuser_ref;
    return $cpuser_ref->{'IP'};

}

sub _get_shared_ip_to_maindomain_map {
    my ( $self, $main_shared_ip, $TRUE_USER_DOMAINS ) = @_;
    my %SHARED_IP_TO_MAIN_DOMAIN_MAP;
    foreach my $reseller ( 'root', Cpanel::Reseller::getresellerslist() ) {
        my $shared_ip_ref = Cpanel::DIp::IsDedicated::getsharedipslist($reseller);
        next if ( !$shared_ip_ref || !ref $shared_ip_ref || !$shared_ip_ref->[0] || $shared_ip_ref->[0] eq $main_shared_ip );

        # A reseller is only permitted one shared ip
        # since Whostmgr::Resellers::Ips::set_reseller_mainip($reseller, $ip)
        # only takes one ip
        if ( $SHARED_IP_TO_MAIN_DOMAIN_MAP{ $shared_ip_ref->[0] } ) {

            # If multiple resellers are using a shared ip, we default this to the hostname
            # because there's no way to determine which reseller should “win”
            $SHARED_IP_TO_MAIN_DOMAIN_MAP{ $shared_ip_ref->[0] } = $self->{hostname};
        }
        else {
            $SHARED_IP_TO_MAIN_DOMAIN_MAP{ $shared_ip_ref->[0] } = $TRUE_USER_DOMAINS->{$reseller};
        }
    }

    return \%SHARED_IP_TO_MAIN_DOMAIN_MAP;
}

1;
