package Whostmgr::Resellers::Stat;

# cpanel - Whostmgr/Resellers/Stat.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::SysQuota                ();
use Cpanel::LoadModule              ();
use Cpanel::AcctUtils::Domain       ();
use Cpanel::Math                    ();
use Whostmgr::AcctInfo              ();
use Whostmgr::DateTime              ();
use Whostmgr::Bandwidth::Tiny       ();
use Whostmgr::AcctInfo::Plans       ();
use Cpanel::Config::LoadCpUserFile  ();
use Cpanel::Config::LoadUserDomains ();
use Cpanel::AcctUtils::Account      ();
use Whostmgr::Accounts::Tiny        ();
use Whostmgr::ACLS                  ();
use Try::Tiny;

our $ROOT_BW_CACHE_IS_REBUILDING;

=encoding utf-8

=head1 NAME

Whostmgr::Resellers::Stat - Gather stats about a reseller.

=head1 SYNOPSIS

    use Whostmgr::Resellers::Stat;

    my ( $totaldiskused, $totalbwused, $totaldiskalloc, $totalbwalloc, $raccts ) = Whostmgr::Resellers::Stat::statres(0, 0, 'res' => 'reseller');

    $ENV{'REMOTE_USER'} = 'reseller';
    my ( $totaldiskused, $totalbwused, $totaldiskalloc, $totalbwalloc, $raccts ) = Whostmgr::Resellers::Stat::statres(1);

=cut

=head2 statres($usecurrent, $skipuser, %OPTS)

Gather bandwidth, disk usage, and account stats for a reseller.

$usecurrent - If set $ENV{'REMOTE_USER'} will be used to determine the reseller.
              If not set $OPTS{'res'} will be used to determine the reseller.

$skipuser - If set the reseller's usage will be excluded.

%OPTS below can be:

   res              - optional, a specific reseller to check; defaults to operator
   month            - optional, 1-12; defaults to current month in localtime
   year             - optional, 4-digit; defaults to current year in localtime
   filter_suspended - optional, filters out suspended accounts from the results AND totals.
   filter_deleted   - optional, filters out deleted accounts from the results AND totals.

This also sets $Whostmgr::Resellers::ROOT_BW_CACHE_IS_REBUILDING
so that the caller knows whether the bandwidth results are legit.

=over 3

=item Output

=over 3

=item C<SCALAR>

    The total disk space the reseller (unless $skipuser is set) and all their account have used in megabytes.

=item C<SCALAR>

    The total bandwidth the reseller (unless $skipuser is set) and all their account have used in megabytes.

=item C<SCALAR>

    The total disk space the reseller (unless $skipuser is set) and all their account have been allocated in megabytes.

=item C<SCALAR>

    The total bandwidth the reseller (unless $skipuser is set) and all their account have been allocated in megabytes.

=item C<ARRAYREF of HASHREFS>

    An arrayref of hashrefs with stats on each account.  See the example output below.

=back

Example output:

          '174.79',
          '0',
          20,
          '20',
          [
            {
              'suspended' => 0,
              'bandwidthlimit' => '0.00',
              'diskquota' => 0,
              'package' => 'default',
              'user' => 'amiinmaildir',
              'deleted' => 0,
              'domain' => 'amiinmaildir.org',
              'diskused' => '1.56',
              'bandwidthused' => '0.00'
            },
            {
              'bandwidthused' => '0.00',
              'domain' => 'build36.org',
              'diskused' => '2.12',
              'user' => 'build36',
              'deleted' => 0,
              'bandwidthlimit' => '0.00',
              'diskquota' => 0,
              'package' => 'default',
              'suspended' => 0
            },

=back

=cut

sub statres {
    my ( $usecurrent, $skipuser, %OPTS ) = @_;
    my $reseller;
    if ( !$usecurrent ) {
        $reseller = $OPTS{'res'};
    }
    else {
        $reseller = $ENV{'REMOTE_USER'};
    }
    my $domain = Cpanel::AcctUtils::Domain::getdomain($reseller);
    my %SUS    = Whostmgr::AcctInfo::suspendedlist();

    my $filter_suspended = $OPTS{'filter_suspended'} ? 1 : 0;
    my $filter_deleted   = $OPTS{'filter_deleted'}   ? 1 : 0;
    my $month            = $OPTS{'month'};
    my $year             = $OPTS{'year'};
    if ( !length $month ) { $month = Whostmgr::DateTime::getmonth(); }
    if ( !length $year )  { $year  = Whostmgr::DateTime::getyear(); }

    my %BWLIMITS;
    if ( !$OPTS{'skip_cache'} ) {

        # If skip_cache is passed the bandwidth limit file
        # may not be updated yet because we are doing a mass
        # modify
        Whostmgr::Bandwidth::Tiny::loaduserbwlimits( \%BWLIMITS, 1, 1 );
    }
    my $userplan_ref = Whostmgr::AcctInfo::Plans::loaduserplans();
    my %DOMAINS;
    Cpanel::Config::LoadUserDomains::loadtrueuserdomains( \%DOMAINS, 1 );

    my %DOMAINLIST;
    Cpanel::Config::LoadUserDomains::loaduserdomains( \%DOMAINLIST, 0, 1 );

    my %ACCTS    = Whostmgr::AcctInfo::getaccts($reseller);
    my $numaccts = 0;
    foreach my $discard ( sort keys %ACCTS ) {
        delete $ACCTS{$discard} if $ACCTS{$discard} ne $reseller;

        next if ( !Cpanel::AcctUtils::Account::accountexists($discard) );
        $numaccts++;
    }

    my $DUSERS_ref = Whostmgr::Accounts::Tiny::loaddeletedusers( $reseller, 1 );
    foreach my $duser ( keys %{$DUSERS_ref} ) {
        if ( $ACCTS{$duser} ) {
            $DUSERS_ref->{$duser}{'DELETED'} = 0;
        }
        else {
            $ACCTS{$duser} = 1;
        }
    }

    my ( $qrused, $qrlimit ) = Cpanel::SysQuota::analyzerepquotadata( skip_cache => $OPTS{'skip_cache'} );
    my %USED  = %{$qrused};
    my %LIMIT = %{$qrlimit};

    my $total_disk_used;
    my $total_bandwidth_limit;
    my $total_bandwidth_used;
    my $total_disk_limit;
    my %PLAN_COUNT;
    my @ACCTLIST;

    my $user_bwusage_hr = _get_user_bwusage_hr( $month, $year, [ keys %ACCTS ] );

    foreach my $acct ( sort keys %ACCTS ) {
        next if ( defined $skipuser && $acct eq $skipuser && $skipuser ne "" );
        my $deleted = $DUSERS_ref->{$acct}{'DELETED'} || 0;
        next if $filter_deleted && $deleted;
        my $suspended = $deleted || $SUS{$acct};
        next if $filter_suspended && $suspended;

        $USED{$acct}  = $USED{$acct}  ? Cpanel::Math::_floatNum( ( $USED{$acct} / 1024 ),  2 ) : 0;    #convert to megs
        $LIMIT{$acct} = $LIMIT{$acct} ? Cpanel::Math::_floatNum( ( $LIMIT{$acct} / 1024 ), 2 ) : 0;    #convert to megs

        my %CPDATA;

        if ( $DUSERS_ref->{$acct}{'DELETED'} ) {
            $CPDATA{'DOMAIN'}  = $DUSERS_ref->{$acct}{'DNS'};
            $CPDATA{'DOMAINS'} = $DUSERS_ref->{$acct}{'DNSLIST'};
            $CPDATA{'PLAN'}    = 'deleted account';
            $CPDATA{'BWLIMIT'} = 0;
        }
        else {
            # If skip_cache is passed the bandwidth limit file
            # may not be updated yet because we are doing a mass
            # modify

            $CPDATA{'BWLIMIT'} = $OPTS{'skip_cache'} ? Cpanel::Config::LoadCpUserFile::loadcpuserfile($acct)->{'BWLIMIT'} : $BWLIMITS{$acct};
            $CPDATA{'DOMAIN'}  = $DOMAINS{$acct};
            $CPDATA{'DOMAINS'} = $DOMAINLIST{$acct};
            $CPDATA{'PLAN'}    = $userplan_ref->{$acct};
        }

        my $domain = $CPDATA{'DOMAIN'};
        $total_disk_used  += $USED{$acct};
        $total_disk_limit += $LIMIT{$acct};

        my $bw_bytes = $user_bwusage_hr->{$acct} || 0;
        my $bw_mib   = Cpanel::Math::_floatNum( ( $bw_bytes / (1048576) ), 2 );

        $total_bandwidth_used += $bw_mib;

        my $bwlimit = ( $CPDATA{'BWLIMIT'} eq 'unlimited' ) ? 0 : $CPDATA{'BWLIMIT'};
        $bwlimit = Cpanel::Math::_floatNum( ( $bwlimit / (1048576) ), 2 );
        $total_bandwidth_limit += $bwlimit;

        if ( length $CPDATA{'PLAN'} ) {
            $PLAN_COUNT{ $CPDATA{'PLAN'} }++;
        }

        push(
            @ACCTLIST,
            {
                'user'           => $acct,
                'suspended'      => $suspended,
                'deleted'        => int $deleted,
                'domain'         => $domain,
                'package'        => $CPDATA{'PLAN'},
                'diskused'       => $USED{$acct},
                'diskquota'      => $LIMIT{$acct},
                'bandwidthused'  => $bw_mib,
                'bandwidthlimit' => $bwlimit,
            }
        );
    }

    return (
        $total_disk_used,
        $total_bandwidth_used,
        $total_disk_limit,
        $total_bandwidth_limit,
        \@ACCTLIST,
        $month,
        $year
    );
}

#overridden in tests
sub _get_user_bytes_as_hash {
    my ( $month, $year, $users_ar ) = @_;

    return Cpanel::BandwidthDB::RootCache->new_with_wait()->get_user_bytes_as_hash(
        month => $month,
        year  => $year,
        ( $users_ar ? ( users => $users_ar ) : () ),
    );
}

sub _get_user_bwusage_hr {
    my ( $month, $year, $accounts_ar ) = @_;
    my $user_bwusage_hr;
    Cpanel::LoadModule::load_perl_module('Cpanel::BandwidthDB::RootCache');
    try {
        $user_bwusage_hr = _get_user_bytes_as_hash(
            $month,
            $year,
            ( Whostmgr::ACLS::hasroot() ? () : $accounts_ar ),
        );

        $ROOT_BW_CACHE_IS_REBUILDING = 0;
    }
    catch {
        die $_ if !try { $_->isa('Cpanel::Exception::Database::DatabaseCreationInProgress') };

        #Just let this interface report 0 for everything while the cache is rebuilding.
        $user_bwusage_hr = {};

        $ROOT_BW_CACHE_IS_REBUILDING = 1;
    };
    return $user_bwusage_hr;
}

1;
