package Cpanel::SysQuota;

# cpanel - Cpanel/SysQuota.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::DatastoreDir                 ();
use Cpanel::Fcntl::Constants             ();
use Cpanel::JSON::FailOK                 ();
use Cpanel::JSON                         ();
use Cpanel::QuotaMtime                   ();
use Cpanel::Backup::Config               ();
use Cpanel::PwCache                      ();
use Cpanel::Config::LoadCpConf           ();
use Cpanel::Config::LoadConfig           ();
use Cpanel::SysQuota::FetchRepQuota      ();
use Cpanel::Debug                        ();
use Cpanel::AccessIds::ReducedPrivileges ();
use Try::Tiny;

use constant {
    _ENOENT => 2,
};

our $VERSION         = 1.8;                # This module will break with a .0 version
our $TTL             = 900;
our $MIN_EXPIRE_TIME = 300;
our $RACE_TIME       = ( $TTL ? 1 : 0 );

our $MAILMAN_DISK_USAGE_STORE  = Cpanel::DatastoreDir::PATH() . '/mailman-disk-usage';
our $MYSQL_DISK_USAGE_STORE    = Cpanel::DatastoreDir::PATH() . '/mysql-disk-usage';
our $POSTGRES_DISK_USAGE_STORE = Cpanel::DatastoreDir::PATH() . '/postgres-disk-usage';

my $repquota_cache;

sub analyzerepquotadata { return _parse_quota_data( '',    @_ ); }
sub fetch_quota_map     { return _parse_quota_data( 'map', @_ ); }

my @PARSE_QUOTA_RETURN_ORDER = qw(
  used
  limit
  version
  inodes_used
  inodes_limit
);

=head1 NAME

Cpanel::SysQuota

=head1 DESCRIPTION

Library for gathering information about the system's quota capabilities.

=cut

sub _parse_quota_data {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ( $parser, %opts ) = @_;
    $parser ||= 'used_limit';
    my $parser_file = $parser eq 'used_limit' ? '' : $parser;

    my $now = time();

    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();    # safe since we do not modify
    my ( $disk_cache_disabled, $cache_is_valid, $json_cache_is_valid ) = _caches_are_valid( $parser, $cpconf, \%opts );

    #memory cache
    if ( $repquota_cache->{$parser} && exists $repquota_cache->{$parser}->{'version'} && $repquota_cache->{$parser}->{'version'} eq $VERSION && $json_cache_is_valid ) {
        $Cpanel::Debug::level > 3 && print STDERR __PACKAGE__ . "::analyzerepquotadata: using memory cache\n";
        return $repquota_cache->{$parser}           if $parser eq 'map';
        return $repquota_cache->{$parser}->{'used'} if !wantarray;
        return @{ $repquota_cache->{$parser} }{@PARSE_QUOTA_RETURN_ORDER};
    }

    #json cache
    if ($json_cache_is_valid) {
        $Cpanel::Debug::level > 3 && print STDERR __PACKAGE__ . "::analyzerepquotadata: using json cache\n";
        $repquota_cache->{$parser} = Cpanel::JSON::FailOK::LoadFile("/var/cpanel/repquota$parser_file.datastore");
        if ( $repquota_cache && $repquota_cache->{$parser}->{'version'} && $repquota_cache->{$parser}->{'version'} eq $VERSION ) {
            $Cpanel::Debug::level > 3 && print STDERR __PACKAGE__ . "::analyzerepquotadata: json cache passed test ($repquota_cache->{$parser}->{'version'} eq $VERSION)\n";
            return $repquota_cache->{$parser}           if $parser eq 'map';
            return $repquota_cache->{$parser}->{'used'} if !wantarray;
            return @{ $repquota_cache->{$parser} }{@PARSE_QUOTA_RETURN_ORDER};
        }
        else {
            $Cpanel::Debug::level > 3 && print STDERR __PACKAGE__ . "::analyzerepquotadata: json cache failed test ($repquota_cache->{$parser}->{'version'} ne $VERSION)\n";
            delete $repquota_cache->{$parser};
        }
    }

    my $backup_dirs_ref = Cpanel::Backup::Config::get_backup_dirs();
    my ( %MAP, %USED, %LIMIT, %INODES_USED, %INODES_LIMIT );
    $repquota_cache = {};
    my ( $good_users, $skipdev, $device, $username, $used, $hard, $inodes_used, $inodes_hard ) = ( 0, 0 );
    foreach my $quotalines ( split( /\n/, fetch_system_repquota( $disk_cache_disabled, $cache_is_valid, $cpconf ) ) ) {
        if ( index( $quotalines, '***' ) == 0 ) {
            $device = ( split( /\s+/, $quotalines ) )[-1];
            if ( !check_backup_dirs( $quotalines, $backup_dirs_ref ) ) {    # If the backupdir is > 1 then
                                                                            # we can exclude it -- ie not /
                $skipdev = 1;
                next;
            }
            elsif ( $quotalines =~ /^\*\*\*.*backup/ ) {
                $skipdev = 1;
                next;
            }
            elsif ($skipdev) {
                $skipdev = 0 if ( $quotalines =~ /^\*\*\*/ );
                next;
            }
        }
        elsif ( $quotalines =~ m{ \A (\S+) \s+ [-+]{2} \s+ (\d+) \s+ \d+ \s+ (\d+) \s* (\d*) \s* (\d*) }xms ) {
            ( $username, $used, $hard, $inodes_used, $inodes_hard ) = ( $1, $2, $3, $4, $5 );

            #keep track of good users.. we only need to resolv uid if its all uids.. If we see 10 good usernames
            #we know that its just files owned by users who do not have a username (just uids)
            if ( $good_users <= 10 && $username =~ m{ \A [#]? (\d+) \z }xms ) {
                if ( $Cpanel::Debug::level > 3 ) {
                    print STDERR __PACKAGE__ . "::analyzerepquotadata: resolving uid: $1 ($username)\n";
                }
                $username = ( Cpanel::PwCache::getpwuid_noshadow($1) )[0];
                $good_users--;
            }
            if ( defined $username && $username ne '' && $username !~ m{ \A [#]? \d+ \z }xms && ( $hard || $used ) ) {
                $good_users++;
                if ( $parser eq 'map' ) {
                    $MAP{$device}{$username} = [ $used, ( ( $hard > 0 ) ? $hard : 0 ) ];
                }
                else {
                    $USED{$username}        += $used        if $used;
                    $INODES_USED{$username} += $inodes_used if $inodes_used;
                    $LIMIT{$username}        = ( ( $hard > 0 )        ? $hard        : 0 ) if $hard;
                    $INODES_LIMIT{$username} = ( ( $inodes_hard > 0 ) ? $inodes_hard : 0 ) if $inodes_hard;
                }
            }
        }
    }
    if ( $cpconf->{'disk_usage_include_mailman'} ) {
        {
            my $mailman_disk_usage_hashref = Cpanel::Config::LoadConfig::loadConfig( $MAILMAN_DISK_USAGE_STORE, -1, ':\s+' );
            if ( $parser eq 'map' ) {
                %{ $MAP{'mailman'} } = map { $_ => [ int( $mailman_disk_usage_hashref->{$_} / 1024 ) ] } grep { $mailman_disk_usage_hashref->{$_} } keys %{$mailman_disk_usage_hashref};
            }
            else {
                foreach my $user ( grep { $mailman_disk_usage_hashref->{$_} } keys %{$mailman_disk_usage_hashref} ) {
                    $USED{$user} += int( $mailman_disk_usage_hashref->{$user} / 1024 );
                }
            }
        }
    }

    if ( $cpconf->{'disk_usage_include_sqldbs'} ) {
        {
            my $mysql_disk_usage_hashref = Cpanel::Config::LoadConfig::loadConfig( $MYSQL_DISK_USAGE_STORE, -1, ':\s+' );
            if ( $parser eq 'map' ) {
                %{ $MAP{'mysql'} } = map { $_ => [ int( $mysql_disk_usage_hashref->{$_} / 1024 ) ] } grep { $mysql_disk_usage_hashref->{$_} } keys %{$mysql_disk_usage_hashref};
            }
            else {
                foreach my $user ( grep { $mysql_disk_usage_hashref->{$_} } keys %{$mysql_disk_usage_hashref} ) {
                    $USED{$user} += int( $mysql_disk_usage_hashref->{$user} / 1024 );
                }
            }
        }
        {
            my $postgres_disk_usage_hashref = Cpanel::Config::LoadConfig::loadConfig( $POSTGRES_DISK_USAGE_STORE, -1, ':\s+' );
            if ( $parser eq 'map' ) {
                %{ $MAP{'postgres'} } = map { $_ => [ int( $postgres_disk_usage_hashref->{$_} / 1024 ) ] } grep { $postgres_disk_usage_hashref->{$_} } keys %{$postgres_disk_usage_hashref};
            }
            else {
                foreach my $user ( grep { $postgres_disk_usage_hashref->{$_} } keys %{$postgres_disk_usage_hashref} ) {
                    $USED{$user} += int( $postgres_disk_usage_hashref->{$user} / 1024 );
                }
            }
        }
    }

    if ( $parser eq 'map' ) {
        $repquota_cache->{$parser} = {
            'map'     => \%MAP,
            'version' => $VERSION
        };
    }
    else {
        $repquota_cache->{$parser} = {
            'used'         => \%USED,
            'inodes_used'  => \%INODES_USED,
            'limit'        => \%LIMIT,
            'inodes_limit' => \%INODES_LIMIT,
            'version'      => $VERSION
        };
    }

    if ( !$disk_cache_disabled ) {
        $Cpanel::Debug::level > 3 && print STDERR __PACKAGE__ . "::analyzerepquotadata: wrote json cache to /var/cpanel/repquota$parser_file.datastore\n";
        require Cpanel::FileUtils::Write;
        Cpanel::FileUtils::Write::overwrite( "/var/cpanel/repquota$parser_file.datastore", Cpanel::JSON::Dump( $repquota_cache->{$parser} ), 0600 );
    }

    return $repquota_cache->{$parser}           if $parser eq 'map';
    return $repquota_cache->{$parser}->{'used'} if !wantarray;

    return @{ $repquota_cache->{$parser} }{@PARSE_QUOTA_RETURN_ORDER};
}

sub _caches_are_valid {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my $parser      = shift;
    my $parser_file = $parser eq 'used_limit' ? '' : $parser;
    my $cpconf      = shift || Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    my $opts        = shift // {};

    if ( $cpconf->{'disablequotacache'} || $opts->{'skip_cache'} || -e '/proc/vz/veinfo' ) {
        $Cpanel::Debug::level > 3 && print STDERR __PACKAGE__ . "::_caches_are_valid: cache explictly disabled.\n";
        return ( 1, 0, 0 );
    }
    my $now     = time();
    my $is_root = ( $> == 0 ? 1 : 0 );

    my ( $text_cache_size, $text_cache_mtime ) = ( stat('/var/cpanel/repquota.cache') )[ 7, 9 ];
    $text_cache_mtime ||= 0;
    my $text_cache_is_readable                   = ( $is_root || -r _ )                                     ? 1 : 0;
    my $text_cache_is_readable_and_timewarp_safe = ( $text_cache_is_readable && $text_cache_mtime <= $now ) ? 1 : 0;
    my $text_cache_is_newer_then_ttl             = ( ( $text_cache_mtime + $TTL ) > $now )                  ? 1 : 0;
    my $text_cache_is_within_min_expire_time     = ( $text_cache_mtime > ( $now - $MIN_EXPIRE_TIME ) )      ? 1 : 0;

    my ( $serialized_data_size, $serialized_data_mtime ) = ( stat("/var/cpanel/repquota$parser_file.datastore") )[ 7, 9 ];
    $serialized_data_mtime ||= 0;
    my $serialzied_data_is_readable                      = ( $is_root || -r _ )                                               ? 1 : 0;
    my $serialzied_data_is_readable_and_timewarp_safe    = ( $serialzied_data_is_readable && $serialized_data_mtime <= $now ) ? 1 : 0;
    my $serialized_data_is_at_least_as_new_as_text_cache = ( $serialized_data_mtime >= $text_cache_mtime )                    ? 1 : 0;
    my $serialized_data_is_newer_then_ttl                = ( ( $serialized_data_mtime + $TTL ) > $now )                       ? 1 : 0;
    my $serialized_data_is_within_min_expire_time        = ( $serialized_data_mtime > ( $now - $MIN_EXPIRE_TIME ) )           ? 1 : 0;

    # usable quota data is always valid for $MIN_EXPIRE_TIME (Currently 300 seconds)
    # usable quota data is always invalid after $TTL         (Currently 900 seconds)
    # In between $MIN_EXPIRE_TIME and $TTL we look to see if the cache is valid by checking the quota files
    my $quota_mtime;    # only checked if quota data is between $MIN_EXPIRE_TIME and $TTL

    my $text_cache_is_valid      = ( $text_cache_is_readable_and_timewarp_safe && $text_cache_is_newer_then_ttl && ( $text_cache_is_within_min_expire_time || $text_cache_mtime >= ( $quota_mtime ||= Cpanel::QuotaMtime::get_quota_mtime( $text_cache_mtime - $RACE_TIME ) ) ) ) ? 1 : 0;
    my $serialzied_data_is_valid = ( $serialzied_data_is_readable_and_timewarp_safe && $serialized_data_is_at_least_as_new_as_text_cache && $serialized_data_is_newer_then_ttl && ( $serialized_data_is_within_min_expire_time || $serialized_data_mtime >= ( $quota_mtime ||= Cpanel::QuotaMtime::get_quota_mtime( $text_cache_mtime - $RACE_TIME ) ) ) ) ? 1 : 0;
    $Cpanel::Debug::level > 3 && print STDERR __PACKAGE__ . "::_caches_are_valid: quotamtime[$quota_mtime] text_cache[$text_cache_is_valid] (readable:$text_cache_is_readable,mtime:$text_cache_mtime) serialzied_data[$serialzied_data_is_valid] (readable:$serialzied_data_is_readable,mtime:$serialized_data_mtime).\n";

    return ( 0, $text_cache_is_valid, $serialzied_data_is_valid );
}

=head1 FUNCTIONS

=head2 fetch_system_repquota

    HASHREF $repquota = fetch_system_repquota( BOOL $disk_cache_disabled, BOOL $cache_is_valid, HASHREF $cpconf)

Return the status of the system quotas.

=cut

sub fetch_system_repquota {
    my ( $disk_cache_disabled, $cache_is_valid, $cpconf ) = @_;
    $cpconf ||= Cpanel::Config::LoadCpConf::loadcpconf();
    my $repquota_data;

    # If quotas are not enabled 0 size and no data is EXPECTED so we should not
    # ask everytime even if we get 0 back
    if ($cache_is_valid) {
        $Cpanel::Debug::level > 3 && print STDERR __PACKAGE__ . "::fetch_system_repquota: using text cache\n";
        if ( open( my $quota_cache_fh, '<', '/var/cpanel/repquota.cache' ) ) {
            local $/;
            $repquota_data = readline($quota_cache_fh);
            close($quota_cache_fh);
            $Cpanel::Debug::level > 3 && print STDERR __PACKAGE__ . "::fetch_system_repquota: text cache passed test\n";
            return $repquota_data;
        }
    }

    $Cpanel::Debug::level > 3 && print STDERR __PACKAGE__ . "::fetch_system_repquota: fetching using safe_fetch_repquota\n";
    my $err;
    try {
        $repquota_data = Cpanel::SysQuota::FetchRepQuota::fetch_repquota_with_timeout( $cpconf->{'repquota_timeout'} );
    }
    catch {
        $err = $_;
    };

    if ($err) {
        Cpanel::Debug::log_warn($err);
        return undef;
    }
    if ( !$disk_cache_disabled ) {
        $Cpanel::Debug::level > 3 && print STDERR __PACKAGE__ . "::fetch_system_repquota: saving text cache\n";
        if ( sysopen( my $quota_cache_fh, '/var/cpanel/repquota.cache', $Cpanel::Fcntl::Constants::O_WRONLY | $Cpanel::Fcntl::Constants::O_TRUNC | $Cpanel::Fcntl::Constants::O_CREAT, 0600 ) ) {
            print {$quota_cache_fh} $repquota_data;
            close($quota_cache_fh);
        }
    }

    return $repquota_data;
}

sub check_backup_dirs {
    my ( $quotalines, $backupdirs_ref ) = @_;
    foreach my $backupdir ( @{$backupdirs_ref} ) {
        return 0 if $backupdir && length($backupdir) > 1 && $quotalines =~ /^\*\*\*.*$backupdir/o;
    }
    return 1;
}

#XXX tight coupling with Cpanel/SysQuota/Cache.pm.
sub _purge_memory_cache {
    $repquota_cache = {};
    return;
}

=head2 userquota_probably_broken

    BOOL $broken = userquota_probably_broken()

Check all available homematch partitions for whether I<any> of their configured mountpoints in fstab mismatches the current mounted disk for that mountpoint.
This is a problem particularly under vzquota,
though there are other filesystems in which this is probably troublesome too.

This doesn't mean your homedir's quota is necessarily broken;
this is for when checking in detail is simply too costly,
and a rougher grained measure like this will do.

=cut

sub userquota_probably_broken {

    require Cpanel::Devices;
    require Cpanel::Filesys::Home;

    my @dirs = Cpanel::Filesys::Home::get_all_homedirs();
    foreach my $dir (@dirs) {

        local $@;

        #If we don't get a solid answer on either of these questions, we probably are wrecked anyways
        my ( $rdev, $ruuid ) = eval { Cpanel::Devices::get_device_for_file($dir) };
        return 1 unless $rdev;

        my ( $cdev, $cuuid ) = eval { Cpanel::Devices::get_configured_device_for_file($dir) };
        return 1 unless $cdev;

        #If the device IDs or UUIDs don't match, chances are quotas are broken
        return 1 if ( $rdev ne $cdev || $ruuid ne $cuuid );
    }
    return 0;
}

=head2 @corrected_files = correct_user_maildirsize_permissions()

Make sure the permissions on the maildirsize files is correct for our email users
For each homedir we need to find all the maildirsize files there and check they are 0600
If they aren't sending mails will be broken due to quota

=cut

sub correct_user_maildirsize_permissions {

    require Cpanel::Config::Users;
    require Cpanel::Email::Accounts;
    require Cpanel::Config::LoadCpUserFile;

    my @users = Cpanel::Config::Users::getcpusers();
    my %user_map;
    foreach my $user ( sort @users ) {

        my $user_has_some_disk_space = eval {
            Cpanel::AccessIds::ReducedPrivileges::call_as_user(
                sub {
                    my $ok = eval {
                        require Cpanel::Quota;
                        require Cpanel;
                        Cpanel::initcp();
                        Cpanel::Quota::has_reached_quota() ? 0 : 1;
                    };
                    warn $@ if $@;
                    return $ok;
                },
                $user
            );
        };

        if ( !$user_has_some_disk_space ) {
            $Cpanel::Debug::level > 3 && print STDERR __PACKAGE__ . "::correct_user_maildirsize_permissions: skipping user '$user' Disk Quota Full.\n";
            next;
        }

        local $Cpanel::user = $user;    # PPI NO PARSE - globals
        my $cpuser_ref = Cpanel::Config::LoadCpUserFile::loadcpuserfile($user);
        local @Cpanel::DOMAINS = ( $cpuser_ref->{'DOMAIN'}, $cpuser_ref->{'DOMAINS'} ? @{ $cpuser_ref->{'DOMAINS'} } : () );
        local $Cpanel::homedir = Cpanel::PwCache::gethomedir($user);

        my @maildirsize_files = ("$Cpanel::homedir/mail/maildirsize");    # PPI NO PARSE - globals

        my ($popaccts_ref) = Cpanel::Email::Accounts::manage_email_accounts_db(
            'event'       => 'fetch',
            'no_validate' => 1,
            'no_disk'     => 1,
        );

        foreach my $domain ( keys(%$popaccts_ref) ) {
            push( @maildirsize_files, ( map { "$Cpanel::homedir/mail/$domain/$_/maildirsize" } keys( %{ $popaccts_ref->{$domain}->{accounts} } ) ) );    # PPI NO PARSE - globals
        }
        $user_map{$user} = \@maildirsize_files;
    }

    my @badfiles;
    foreach my $user ( sort keys(%user_map) ) {
        Cpanel::AccessIds::ReducedPrivileges::call_as_user(
            sub {
                foreach my $mdfile ( @{ $user_map{$user} } ) {
                    local $!;
                    my ( undef, undef, $mode ) = stat $mdfile;

                    if ($!) {
                        warn "Error accessing $mdfile: $!" if $! != _ENOENT();

                        #In the ENOENT case, just skip, they haven't accessed email yet
                        next;
                    }

                    # Handle naughty users
                    next unless -f _;

                    if ( ( $mode & 0777 ) != 0600 ) {
                        chmod( 0600, $mdfile ) or warn "Could not chown $mdfile to correct permissions (0600): $!";
                        push( @badfiles, $mdfile );
                    }
                }
            },
            $user,
        );
    }

    return @badfiles;

}

1;
