package Whostmgr::API::1::Resellers;

# cpanel - Whostmgr/API/1/Resellers.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::AcctUtils::Account     ();
use Whostmgr::ACLS                 ();
use Cpanel::Reseller               ();
use Cpanel::Validate::Domain::Tiny ();
use Whostmgr::DateTime             ();
use Cpanel::Imports                ();
use Cpanel::NAT                    ();
use Cpanel::Validate::Integer      ();
use Whostmgr::Limits::Resellers    ();
use Whostmgr::Resellers::Ips       ();
use Whostmgr::Resellers::Setup     ();
use Whostmgr::Resellers::List      ();
use Whostmgr::AccessHash           ();
use Whostmgr::Authz                ();
use Whostmgr::API::1::Utils        ();
use Whostmgr::Math                 ();

use constant NEEDS_ROLE => {
    accesshash              => undef,
    acctcounts              => undef,
    get_remote_access_hash  => undef,
    getresellerips          => undef,
    listresellers           => undef,
    resellerstats           => undef,
    setacls                 => undef,
    setresellerips          => undef,
    setresellerlimits       => undef,
    setresellermainip       => undef,
    setresellernameservers  => undef,
    setresellerpackagelimit => undef,
    setupreseller           => undef,
    suspendreseller         => undef,
    terminatereseller       => undef,
    unsetupreseller         => undef,
    unsuspendreseller       => undef,
};

#NOTE: “user” defaults to the operating user
#
sub acctcounts {
    my ( $args, $metadata ) = @_;

    if ( !defined $args->{'user'} ) {
        $args->{'user'} = $ENV{'REMOTE_USER'};
    }

    my $user = $args->{'user'};

    Whostmgr::Authz::verify_account_access($user);

    my $result;
    my $reason;
    my $reseller_data;

    if ( !Cpanel::Reseller::isreseller($user) ) {
        $result = 0;
        $reason = 'Not a reseller.';
    }

    if ( !defined $result ) {
        require Whostmgr::Resellers;
        $reseller_data           = Whostmgr::Resellers::get_account_counts($user);
        $reseller_data->{'user'} = $user;
        $result                  = 1;
    }

    $metadata->{'result'} = $result ? 1    : 0;
    $metadata->{'reason'} = $result ? 'OK' : $reason;
    return if !defined $reseller_data;
    return { 'reseller' => $reseller_data };
}

sub getresellerips {
    my ( $args, $metadata ) = @_;
    my $user = $args->{'user'};

    Whostmgr::Authz::verify_account_access($user);

    my $out_array_ref = [];
    my $all_ips_allowed;
    my ( $result, $reason ) = Whostmgr::Resellers::Ips::get_reseller_ips( $user, $out_array_ref, \$all_ips_allowed );

    foreach my $ip ( @{$out_array_ref} ) {
        $ip = Cpanel::NAT::get_public_ip($ip);
    }

    $metadata->{'result'} = $result ? 1    : 0;
    $metadata->{'reason'} = $result ? 'OK' : $reason;

    my %rs;
    if ($result) {
        $rs{'ip'} = $out_array_ref;
        if ($all_ips_allowed) {
            $rs{'all'} = 1;
        }
    }
    return \%rs;
}

sub listresellers {
    my ( undef, $metadata ) = @_;
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return { 'reseller' => [ keys %{ Whostmgr::Resellers::List::list() } ] };
}

sub resellerstats {
    my ( $args, $metadata ) = @_;

    my $user             = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'user' );
    my $filter_suspended = $args->{'filter_suspended'} ? 1 : 0;
    my $filter_deleted   = $args->{'filter_deleted'}   ? 1 : 0;
    my $month            = $args->{'month'};
    my $year             = $args->{'year'};

    my $current_year  = Whostmgr::DateTime::getyear();
    my $current_month = Whostmgr::DateTime::getmonth();

    if ( defined $year ) {
        if ( !length($year) || $year =~ tr<0-9><>c || $year < 1996 || $year > $current_year ) {
            die "Invalid “year”: $year\n";
        }
    }

    $year ||= $current_year;

    if ( defined $month ) {
        if ( !length($month) || $month =~ tr<0-9><>c || $month < 1 || $month > 12 || ( $year == $current_year && $month > $current_month ) ) {
            die "Invalid “month”: $month\n";
        }
    }

    $month ||= $current_month;

    Cpanel::AcctUtils::Account::accountexists_or_die($user);
    if ( !Cpanel::Reseller::isreseller($user) ) {
        die "The user “$user” is not a reseller.";
    }
    require Whostmgr::Resellers::Stat;
    my (
        $totaldiskused,
        $totalbwused,
        $totaldiskalloc,
        $totalbwalloc,
        $raccts,
        $datamonth,
        $datayear
    ) = Whostmgr::Resellers::Stat::statres( 0, '', 'res' => $user, 'month' => $month, 'year' => $year, 'filter_suspended' => $filter_suspended, 'filter_deleted' => $filter_deleted );

    require Whostmgr::Resellers;
    if ($Whostmgr::Resellers::ROOT_BW_CACHE_IS_REBUILDING) {
        $metadata->{'warnings'} = locale()->maketext('Bandwidth totals are unavailable during the rebuild of root’s bandwidth cache database.');
    }

    my $rlimits         = Whostmgr::Limits::Resellers::load_resellers_limits($user);
    my $type            = $rlimits->{'limits'}->{'resources'}->{'type'};
    my $bandwidthlimit  = 0;
    my $diskquota       = 0;
    my $overselling     = $rlimits->{'limits'}->{'resources'}->{'overselling'};
    my $bwoverselling   = 0;
    my $diskoverselling = 0;
    if ( $overselling->{'enabled'} ) {
        $bwoverselling   = $overselling->{'type'}->{'bw'};
        $diskoverselling = $overselling->{'type'}->{'disk'};
    }
    if ( $rlimits->{'limits'}->{'resources'}->{'enabled'} ) {
        $bandwidthlimit = int( $type->{'bw'}   || 0 );
        $diskquota      = int( $type->{'disk'} || 0 );
    }
    my %rs = (
        'diskused'        => Whostmgr::Math::unsci($totaldiskused),
        'totalbwused'     => Whostmgr::Math::unsci($totalbwused),
        'totaldiskalloc'  => Whostmgr::Math::unsci($totaldiskalloc),
        'totalbwalloc'    => Whostmgr::Math::unsci($totalbwalloc),
        'user'            => $user,
        'acct'            => $raccts,
        'bandwidthlimit'  => $bandwidthlimit,
        'diskquota'       => $diskquota,
        'bwoverselling'   => $bwoverselling   ? 1 : 0,
        'diskoverselling' => $diskoverselling ? 1 : 0,
        'month'           => $datamonth,
        'year'            => $datayear
    );
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    return { 'reseller' => \%rs };
}

sub setacls {
    my ( $args, $metadata ) = @_;
    my @acl_list;
    my %acls_set;
    my $user = $args->{'user'} || $args->{'reseller'};

    if ( !length $user ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'No reseller specified.';
        return;
    }

    if ( $args->{'acllist'} ) {
        my $acllist  = $args->{'acllist'};
        my $acllists = Whostmgr::ACLS::list_acls($acllist);
        foreach my $acl ( keys %{ $acllists->{$acllist} } ) {
            next if ( $acllists->{$acllist}->{$acl} != 1 );
            $acls_set{ 'acl-' . $acl } = 1;
            push @acl_list, $acl;
        }
    }
    else {
        foreach my $acl ( keys %$args ) {
            next if ( $acl !~ /^acl-/ );
            $acl =~ s/^acl-//g;
            $acls_set{ 'acl-' . $acl } = 1;
            push @acl_list, $acl;
        }
    }

    require Whostmgr::Resellers;
    my ( $result, $reason ) = Whostmgr::Resellers::set_reseller_acls( $user, \%acls_set );
    $metadata->{'result'} = $result ? 1    : 0;
    $metadata->{'reason'} = $result ? 'OK' : $reason;
    return { 'acl' => \@acl_list };
}

sub setresellerips {
    my ( $args, $metadata ) = @_;
    my $user     = $args->{'user'};
    my $delegate = exists $args->{'delegate'} ? $args->{'delegate'} : 1;
    my @ips      = split( /,/, Cpanel::NAT::get_local_ip( $args->{'ips'} ) );
    my ( $result, $reason ) = Whostmgr::Resellers::Ips::set_reseller_ips( $user, $delegate, @ips );
    $metadata->{'result'} = $result ? 1    : 0;
    $metadata->{'reason'} = $result ? 'OK' : $reason;
    return if !$result;
    return getresellerips( $args, $metadata );
}

sub _validate_unsigned_if_exists {
    my ( $args, $name ) = @_;

    if ( exists $args->{$name} ) {
        Cpanel::Validate::Integer::unsigned( $args->{$name}, $name );
    }

    return;
}

sub setresellerlimits {
    my ( $args, $metadata ) = @_;

    my $user = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'user' );

    _validate_unsigned_if_exists( $args, 'bandwidth_limit' );
    _validate_unsigned_if_exists( $args, 'diskspace_limit' );
    _validate_unsigned_if_exists( $args, 'account_limit' );

    my %limit_settings = ( 'user' => $user );
    require Whostmgr::Resellers;
    Whostmgr::Resellers::_set_if_exists( $args, 'enable_overselling',           \%limit_settings );
    Whostmgr::Resellers::_set_if_exists( $args, 'enable_overselling_bandwidth', \%limit_settings );
    Whostmgr::Resellers::_set_if_exists( $args, 'enable_overselling_diskspace', \%limit_settings );
    Whostmgr::Resellers::_set_if_exists( $args, 'enable_resource_limits',       \%limit_settings );
    Whostmgr::Resellers::_set_if_exists( $args, 'bandwidth_limit',              \%limit_settings );
    Whostmgr::Resellers::_set_if_exists( $args, 'diskspace_limit',              \%limit_settings );
    Whostmgr::Resellers::_set_if_exists( $args, 'enable_account_limit',         \%limit_settings );
    Whostmgr::Resellers::_set_if_exists( $args, 'account_limit',                \%limit_settings );
    Whostmgr::Resellers::_set_if_exists( $args, 'enable_package_limits',        \%limit_settings );
    Whostmgr::Resellers::_set_if_exists( $args, 'enable_package_limit_numbers', \%limit_settings );

    my ( $result, $reason ) = Whostmgr::Resellers::set_reseller_limits(%limit_settings);
    $metadata->{'result'} = $result ? 1    : 0;
    $metadata->{'reason'} = $result ? 'OK' : $reason;
    return;
}

sub setresellermainip {
    my ( $args, $metadata ) = @_;
    my $user = $args->{'user'};
    my $ip   = $args->{'ip'};

    $ip = Cpanel::NAT::get_local_ip($ip);

    if ( !Cpanel::AcctUtils::Account::accountexists($user) ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'Account does not exist.';
        return;
    }
    elsif ( !Cpanel::Reseller::isreseller($user) ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'Not a reseller.';
        return;
    }
    my ( $result, $reason ) = Whostmgr::Resellers::Ips::set_reseller_mainip( $user, $ip );
    $metadata->{'result'} = $result ? 1    : 0;
    $metadata->{'reason'} = $result ? 'OK' : $reason;
    return;
}

sub setresellernameservers {
    my ( $args, $metadata ) = @_;
    my $user = $args->{'user'};

    Whostmgr::Authz::verify_account_access($user);

    my @nameservers = split( /\,/, $args->{'nameservers'} );
    chomp @nameservers;
    my $nameservers_are_valid = 1;
    my $result;
    my $reason;

    foreach my $ns (@nameservers) {
        if ( !Cpanel::Validate::Domain::Tiny::validdomainname($ns) ) {
            undef $nameservers_are_valid;
            $result = 0;
            $reason = 'A specified nameserver is invalid.';
            last;
        }
    }

    if ($nameservers_are_valid) {
        require Whostmgr::Resellers;
        ( $result, $reason ) = Whostmgr::Resellers::set_nameservers( $user, \@nameservers );
    }

    $metadata->{'result'} = $result ? 1    : 0;
    $metadata->{'reason'} = $result ? 'OK' : $reason;
    return;
}

sub setresellerpackagelimit {
    my ( $args, $metadata ) = @_;
    my $no_limit = 0;
    if ( exists $args->{'no_limit'} ) {
        $no_limit = $args->{'no_limit'};
    }

    my @limit_args = (
        $args->{'user'},
        $no_limit,
        $args->{'package'},
        $args->{'allowed'},
        $args->{'number'}
    );
    require Whostmgr::Resellers;
    my ( $result, $reason ) = Whostmgr::Resellers::set_reseller_package_limit(@limit_args);
    $metadata->{'result'} = $result ? 1    : 0;
    $metadata->{'reason'} = $result ? 'OK' : $reason;
    return;
}

sub setupreseller {
    my ( $args, $metadata ) = @_;
    my $user      = $args->{'user'};
    my $makeowner = $args->{'makeowner'} ? 1 : 0;
    my ( $result, $reason ) = Whostmgr::Resellers::Setup::setup_reseller_and_sync_web_vhosts( $user, $makeowner );
    $metadata->{'result'} = $result ? 1    : 0;
    $metadata->{'reason'} = $result ? 'OK' : $reason;
    return;
}

sub suspendreseller {
    my ( $args, $metadata ) = @_;
    my $user          = $args->{'user'};
    my $why           = $args->{'reason'};
    my $disallow      = $args->{'disallow'};
    my $reseller_only = $args->{'reseller-only'} || 0;

    require Whostmgr::Resellers;
    my ( $result, $reason, $output ) = Whostmgr::Resellers::suspend_reseller( $user, $why, $disallow, $reseller_only );

    if ( defined $output ) {
        $metadata->{'output'}->{'raw'} = $output;
    }
    $metadata->{'result'} = $result ? 1    : 0;
    $metadata->{'reason'} = $result ? 'OK' : $reason;
    return;
}

sub terminatereseller {
    my ( $args, $metadata ) = @_;
    my $user = $args->{'user'};

    if ( !Cpanel::Reseller::isreseller($user) ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'Not a reseller.';
        return;
    }

    my @killed_acct_list;
    my $extra_reasons = '';
    my ( $result, $reason ) = Whostmgr::Resellers::Setup::_unsetupreseller( $user, 1 );
    if ($result) {
        require Whostmgr::Resellers::Kill;
        my $status = Whostmgr::Resellers::Kill::kill_owned_accts( $user, int $args->{'terminatereseller'} );
        while ( my ( $u, $kill_result ) = each %$status ) {
            my %acct;
            $acct{'user'}   = $u;
            $acct{'result'} = $kill_result->{'status'};
            $acct{'reason'} = $kill_result->{'statusmsg'};
            if ( length $kill_result->{'rawout'} ) {
                $acct{'output'}->{'raw'} = $kill_result->{'rawout'};
            }
            push @killed_acct_list, \%acct;
            if ( !$acct{'result'} ) {
                $result = 0;
                if ( length $extra_reasons ) {
                    $extra_reasons .= ' ';
                }
                $extra_reasons .= $acct{'reason'} || ( 'Failed to terminate ' . $u . '.' );
            }
        }
    }

    if ( !$result ) {
        $reason = length $reason ? $reason . ' ' . $extra_reasons : $extra_reasons;
    }

    $metadata->{'result'} = $result ? 1 : 0;
    $metadata->{'reason'} = $reason || ( $result ? 'OK' : 'Failed to terminate reseller.' );
    return if !scalar @killed_acct_list;
    return { 'acct' => \@killed_acct_list };
}

sub unsetupreseller {
    my ( $args,   $metadata ) = @_;
    my ( $result, $reason )   = Whostmgr::Resellers::Setup::unsetup_reseller_and_sync_web_vhosts( $args->{'user'} );
    $metadata->{'result'} = $result ? 1    : 0;
    $metadata->{'reason'} = $result ? 'OK' : $reason;
    return;
}

sub unsuspendreseller {
    my ( $args, $metadata ) = @_;
    my $user          = $args->{'user'};
    my $reseller_only = $args->{'reseller-only'} || 0;

    require Whostmgr::Resellers;
    my ( $result, $reason, $output ) = Whostmgr::Resellers::unsuspend_reseller( $user, $reseller_only );

    if ( defined $output ) {
        $metadata->{'output'}->{'raw'} = $output;
    }

    $metadata->{'result'} = $result ? 1    : 0;
    $metadata->{'reason'} = $result ? 'OK' : $reason;
    return;
}

sub accesshash {
    my ( $args, $metadata ) = @_;
    my $user = $args->{'user'} || $ENV{'REMOTE_USER'};
    my ( $result, $reason, $data );
    if ( $args->{'generate'} ) {
        ( $result, $reason, $data ) = Whostmgr::AccessHash::generate_access_hash($user);
    }
    else {
        ( $result, $reason, $data ) = Whostmgr::AccessHash::get_access_hash($user);
    }
    $metadata->{'result'} = $result;
    $metadata->{'reason'} = $reason;
    $data =~ s/[\r\n]//g if defined $data;
    return { 'accesshash' => $data };
}

sub get_remote_access_hash {
    my ( $args, $metadata ) = @_;

    # do SSL check here

    if ( !exists $args->{'username'} ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'get_remote_access_hash requires that "username" is defined.';
        return;
    }
    if ( !exists $args->{'password'} ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'get_remote_access_hash requires that "password" is defined.';
        return;
    }
    if ( !exists $args->{'host'} ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'get_remote_access_hash requires that "host" is defined.';
        return;
    }
    my ( $result, $reason, $data ) = Whostmgr::AccessHash::get_remote_access_hash( $args->{'host'}, $args->{'username'}, $args->{'password'}, $args->{'generate'} );
    $metadata->{'result'} = $result;
    $metadata->{'reason'} = $reason;
    return { 'accesshash' => $data };
}

1;
