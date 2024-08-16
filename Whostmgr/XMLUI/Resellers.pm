package Whostmgr::XMLUI::Resellers;

# cpanel - Whostmgr/XMLUI/Resellers.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::AcctUtils::Account     ();
use Whostmgr::ACLS                 ();
use Cpanel::ResellerFunctions      ();
use Cpanel::Reseller               ();
use Cpanel::Validate::Domain::Tiny ();
use Cpanel::NAT                    ();
use Whostmgr::Limits::Resellers    ();
use Whostmgr::Resellers            ();
use Whostmgr::Resellers::Ips       ();
use Whostmgr::Resellers::Kill      ();
use Whostmgr::Resellers::Setup     ();
use Whostmgr::Resellers::Stat      ();
use Whostmgr::Resellers::List      ();
use Whostmgr::XMLUI                ();
use Whostmgr::ApiHandler           ();

sub setacls {
    my %OPTS = @_;

    my @RSD;
    my @ACLLIST;
    my $reseller = $OPTS{'reseller'};
    if ( $OPTS{'acllist'} ) {
        my $acllist  = $OPTS{'acllist'};
        my $acllists = Whostmgr::ACLS::list_acls($acllist);
        delete @OPTS{ keys %OPTS };
        foreach my $acl ( keys %{ $acllists->{$acllist} } ) {
            next if ( $acllists->{$acllist}->{$acl} != 1 );
            $OPTS{ 'acl-' . $acl } = 1;
            push @ACLLIST, $acl;
        }
    }
    else {
        foreach my $acl ( keys %OPTS ) {
            next if ( $acl !~ /^acl-/ );
            $acl =~ s/^acl-//g;
            push @ACLLIST, $acl;
        }
    }

    my @status = Whostmgr::Resellers::set_reseller_acls( $reseller, \%OPTS );
    push( @RSD, { status => $status[0], statusmsg => $status[1], acls => \@ACLLIST } );

    Whostmgr::XMLUI::xmlencode( \@RSD );

    my %RES;
    $RES{'result'} = \@RSD;
    return Whostmgr::ApiHandler::out( \%RES, RootName => 'setacls', NoAttr => 1 );
}

sub setupreseller {
    my %OPTS = @_;

    my @RSD;
    my @status = Whostmgr::Resellers::Setup::setup_reseller_and_sync_web_vhosts( $OPTS{'user'}, $OPTS{'makeowner'} );
    push( @RSD, { status => $status[0], statusmsg => $status[1] } );

    Whostmgr::XMLUI::xmlencode( \@RSD );

    my %RES;
    $RES{'result'} = \@RSD;
    return Whostmgr::ApiHandler::out( \%RES, RootName => 'setupreseller', NoAttr => 1 );
}

sub unsetupreseller {
    my %OPTS = @_;

    my @RSD;
    my @status = Whostmgr::Resellers::Setup::unsetup_reseller_and_sync_web_vhosts( $OPTS{'user'} );

    push( @RSD, { status => $status[0], statusmsg => $status[1] } );
    Whostmgr::XMLUI::xmlencode( \@RSD );

    my %RES;
    $RES{'result'} = \@RSD;
    return Whostmgr::ApiHandler::out( \%RES, RootName => 'unsetupreseller', NoAttr => 1 );
}

sub resellerstats {
    my %OPTS     = @_;
    my $reseller = $OPTS{'reseller'};
    my ( $totaldiskused, $totalbwused, $totaldiskalloc, $totalbwalloc, $raccts ) = Whostmgr::Resellers::Stat::statres( 0, '', res => $reseller );

    my %RES;
    if ( !Cpanel::AcctUtils::Account::accountexists($reseller) ) {
        $RES{'result'} = {
            'status'    => 0,
            'statusmsg' => 'Reseller Does Not Exist',
            'reseller'  => $reseller,
        };
    }
    else {
        my $rlimits         = Whostmgr::Limits::Resellers::load_resellers_limits($reseller);
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
            $bandwidthlimit = int $type->{'bw'};
            $diskquota      = int $type->{'disk'};
        }
        $RES{'result'} = {
            'status'          => 1,
            'statusmsg'       => 'Fetched Reseller Data OK',
            'diskused'        => $totaldiskused,
            'totalbwused'     => $totalbwused,
            'totaldiskalloc'  => $totaldiskalloc,
            'totalbwalloc'    => $totalbwalloc,
            'reseller'        => $reseller,
            'accts'           => $raccts,
            'bandwidthlimit'  => $bandwidthlimit,
            'diskquota'       => $diskquota,
            'bwoverselling'   => $bwoverselling   ? 1 : 0,
            'diskoverselling' => $diskoverselling ? 1 : 0,
        };
    }

    return Whostmgr::ApiHandler::out( \%RES, RootName => 'resellerstats', NoAttr => 1 );
}

sub list {

    my @RSD = map { $_ } keys %{ Whostmgr::Resellers::List::list() };

    my %RES;
    $RES{'reseller'} = \@RSD;
    return Whostmgr::ApiHandler::out( \%RES, RootName => 'listresellers', NoAttr => 1 );
}

sub terminate {
    my %OPTS     = @_;
    my $reseller = $OPTS{'reseller'};
    my $verify   = $OPTS{'verify'};

    $verify =~ s/[\n\"]*//g if length $verify;

    my @RSD;
    my $killref;
    if ( !Cpanel::ResellerFunctions::isreseller($reseller) ) {
        push( @RSD, { status => 0, statusmsg => "Reseller $reseller Does not exist" } );
    }
    elsif ( $verify ne "I understand this will irrevocably remove all the accounts owned by the reseller $reseller" ) {
        push(
            @RSD,
            {
                status    => 0,
                statusmsg => "Sorry, you must pass \"I understand this will irrevocably remove all the accounts owned by the reseller $reseller\" in the verify variable before you can use this feature.\n (verify=$verify)"
            }
        );
    }
    else {
        my $resrm = Whostmgr::Resellers::Setup::_unsetupreseller( $reseller, 1 );
        $killref = Whostmgr::Resellers::Kill::kill_owned_accts( $reseller, int $OPTS{'terminatereseller'} );
        push( @RSD, { status => 1, statusmsg => "Account Terminations Complete", accts => $killref, privdelete => $resrm } );
    }

    Whostmgr::XMLUI::xmlencode( \@RSD );

    my %RES;
    $RES{'result'} = \@RSD;
    return Whostmgr::ApiHandler::out( \%RES, RootName => 'terminatereseller', NoAttr => 1 );
}

sub setresellermainip {
    my %OPTS = @_;

    my $user = $OPTS{'user'};
    my $ip   = $OPTS{'ip'};

    $ip = Cpanel::NAT::get_local_ip($ip);

    my ( $result, $msg ) = Whostmgr::Resellers::Ips::set_reseller_mainip( $user, $ip );

    my @RSD;
    push @RSD, { status => $result, statusmsg => $msg };

    Whostmgr::XMLUI::xmlencode( \@RSD );
    my %RES;
    $RES{'result'} = \@RSD;
    return Whostmgr::ApiHandler::out( \%RES, RootName => 'setresellermainip', NoAttr => 1 );
}

sub getresellerips {
    my %OPTS          = @_;
    my $user          = $OPTS{'user'};
    my $out_array_ref = [];
    my $all_ips_allowed;
    my ( $result, $msg ) = Whostmgr::Resellers::Ips::get_reseller_ips( $user, $out_array_ref, \$all_ips_allowed );

    foreach my $ip ( @{$out_array_ref} ) {
        $ip = Cpanel::NAT::get_public_ip($ip);
    }

    my %RES = ( 'result' => [ { status => $result, statusmsg => $msg } ] );
    if ($result) {
        $RES{'ip'} = $out_array_ref;
        if ($all_ips_allowed) {
            $RES{'all'} = 1;
        }
    }
    return Whostmgr::ApiHandler::out( \%RES, RootName => 'getresellerips', NoAttr => 1 );
}

sub setresellerips {
    my %OPTS = @_;

    my $user     = $OPTS{'user'};
    my $delegate = exists $OPTS{'delegate'} ? $OPTS{'delegate'} : 1;
    my @ips      = split( /,/, Cpanel::NAT::get_local_ip( $OPTS{'ips'} ) );

    my ( $result, $msg ) = Whostmgr::Resellers::Ips::set_reseller_ips( $user, $delegate, @ips );

    my @RSD;
    push @RSD, { status => $result, statusmsg => $msg };

    Whostmgr::XMLUI::xmlencode( \@RSD );
    my %RES;
    $RES{'result'} = \@RSD;
    return Whostmgr::ApiHandler::out( \%RES, RootName => 'setresellerips', NoAttr => 1 );
}

sub setresellerlimits {
    my %OPTS = @_;

    my %args = ( 'user' => $OPTS{'user'} );
    Whostmgr::Resellers::_set_if_exists( \%OPTS, 'enable_overselling',           \%args );
    Whostmgr::Resellers::_set_if_exists( \%OPTS, 'enable_overselling_bandwidth', \%args );
    Whostmgr::Resellers::_set_if_exists( \%OPTS, 'enable_overselling_diskspace', \%args );
    Whostmgr::Resellers::_set_if_exists( \%OPTS, 'enable_resource_limits',       \%args );
    Whostmgr::Resellers::_set_if_exists( \%OPTS, 'bandwidth_limit',              \%args );
    Whostmgr::Resellers::_set_if_exists( \%OPTS, 'diskspace_limit',              \%args );
    Whostmgr::Resellers::_set_if_exists( \%OPTS, 'enable_account_limit',         \%args );
    Whostmgr::Resellers::_set_if_exists( \%OPTS, 'account_limit',                \%args );
    Whostmgr::Resellers::_set_if_exists( \%OPTS, 'enable_package_limits',        \%args );
    Whostmgr::Resellers::_set_if_exists( \%OPTS, 'enable_package_limit_numbers', \%args );

    my ( $result, $msg ) = Whostmgr::Resellers::set_reseller_limits(%args);

    my @RSD;
    push @RSD, { status => $result, statusmsg => $msg };

    Whostmgr::XMLUI::xmlencode( \@RSD );
    my %RES;
    $RES{'result'} = \@RSD;
    return Whostmgr::ApiHandler::out( \%RES, RootName => 'setresellerlimits', NoAttr => 1 );
}

sub setresellerpackagelimit {
    my %OPTS = @_;

    my $no_limit = 0;
    if ( exists $OPTS{'no_limit'} ) {
        $no_limit = $OPTS{'no_limit'};
    }

    my @args = ( $OPTS{'user'}, $no_limit, $OPTS{'package'}, $OPTS{'allowed'}, $OPTS{'number'} );
    my ( $result, $msg ) = Whostmgr::Resellers::set_reseller_package_limit(@args);

    my @RSD;
    push @RSD, { status => $result, statusmsg => $msg };

    Whostmgr::XMLUI::xmlencode( \@RSD );
    my %RES;
    $RES{'result'} = \@RSD;
    return Whostmgr::ApiHandler::out( \%RES, RootName => 'setresellerpackagelimit', NoAttr => 1 );
}

sub suspendreseller {
    my %OPTS     = @_;
    my $user     = $OPTS{'user'};
    my $reason   = $OPTS{'reason'};
    my $disallow = $OPTS{'disallow'};

    my ( $result, $msg, $output ) = Whostmgr::Resellers::suspend_reseller( $user, $reason, $disallow );

    my @RSD;
    push @RSD, { status => $result, statusmsg => $msg };

    Whostmgr::XMLUI::xmlencode( \@RSD );
    my %RES;

    if ($output) {
        $RES{'output'} = $output;
    }

    $RES{'result'} = \@RSD;
    return Whostmgr::ApiHandler::out( \%RES, RootName => 'suspendreseller', NoAttr => 1 );
}

sub unsuspendreseller {
    my %OPTS = @_;
    my $user = $OPTS{'user'};

    my ( $result, $msg, $output ) = Whostmgr::Resellers::unsuspend_reseller($user);

    my @RSD;
    push @RSD, { status => $result, statusmsg => $msg };

    Whostmgr::XMLUI::xmlencode( \@RSD );
    my %RES;

    if ($output) {
        $RES{'output'} = $output;
    }

    $RES{'result'} = \@RSD;
    return Whostmgr::ApiHandler::out( \%RES, RootName => 'unsuspendreseller', NoAttr => 1 );
}

sub setresellernameservers {
    my %OPTS        = @_;
    my $user        = $OPTS{'user'};
    my @nameservers = split( /\,/, $OPTS{'nameservers'} );
    chomp @nameservers;
    my $nameservers_are_valid = 1;
    my $result;
    my $msg;

    foreach my $ns (@nameservers) {
        if ( !Cpanel::Validate::Domain::Tiny::validdomainname($ns) ) {
            undef $nameservers_are_valid;
            $result = 0;
            $msg    = 'A specified nameserver is invalid.';
            last;
        }
    }

    if ($nameservers_are_valid) {
        ( $result, $msg ) = Whostmgr::Resellers::set_nameservers( $user, \@nameservers );
    }

    my @RSD;
    push @RSD, { status => $result, statusmsg => $msg };

    Whostmgr::XMLUI::xmlencode( \@RSD );
    my %RES;
    $RES{'result'} = \@RSD;
    return Whostmgr::ApiHandler::out( \%RES, RootName => 'setresellernameservers', NoAttr => 1 );
}

sub acctcounts {
    my %OPTS = @_;
    my $user = $OPTS{'user'};
    my $result;
    my $msg;
    my $reseller;

    if ( !Cpanel::Reseller::isreseller($user) ) {
        $result = 0;
        $msg    = 'Specified user is not a reseller.';
    }

    if ( !defined $result ) {
        $reseller              = Whostmgr::Resellers::get_account_counts($user);
        $reseller->{'account'} = $user;
        $result                = 1;
        $msg                   = 'Obtained reseller account counts.';
    }

    my @RSD = ( { status => $result, statusmsg => $msg } );
    Whostmgr::XMLUI::xmlencode( \@RSD );
    my %RES = ( 'result' => \@RSD );
    if ( defined $reseller ) {
        $RES{'reseller'} = $reseller;
    }
    return Whostmgr::ApiHandler::out( \%RES, RootName => 'acctcounts', NoAttr => 1 );
}

1;
