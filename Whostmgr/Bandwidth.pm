package Whostmgr::Bandwidth;

# cpanel - Whostmgr/Bandwidth.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Whostmgr::Bandwidth::Tiny       ();
use Whostmgr::DateTime              ();
use Cpanel::Userdomains             ();
use Whostmgr::ACLS                  ();
use Whostmgr::AcctInfo::Owner       ();
use Whostmgr::Limits::Resellers     ();
use Whostmgr::Limits::Exceed        ();
use Cpanel::LoadModule              ();
use Cpanel::ArrayFunc               ();
use Cpanel::Time                    ();
use Cpanel::Math                    ();
use Cpanel::BandwidthMgr            ();
use Cpanel::AcctUtils::Load         ();
use Cpanel::AcctUtils::Account      ();
use Cpanel::Config::CpUserGuard     ();
use Cpanel::Config::LoadCpConf      ();
use Cpanel::Config::LoadUserDomains ();
use Cpanel::Config::Users           ();
use Cpanel::Config::LoadUserOwners  ();
use Whostmgr::Math                  ();
use Whostmgr::Resellers::List       ();

*loaduserbwlimits = \&Whostmgr::Bandwidth::Tiny::loaduserbwlimits;

#expects: username, month, year
#
#Incorporates remote bandwidth usage.
#
sub getmonthbwusage {
    my (%opts) = @_;

    die 'Need “username”!' if !length $opts{'username'};

    if ( grep { !$opts{$_} } qw(month year) ) {
        my ( $month, $year ) = ( Cpanel::Time::localtime() )[ 4, 5 ];
        $opts{'month'} ||= $month;
        $opts{'year'}  ||= $year;
    }

    my $bytes_hr = {};
    try {
        Cpanel::LoadModule::load_perl_module('Cpanel::BandwidthDB::RootCache');
        my $bw_cache_obj = Cpanel::BandwidthDB::RootCache->new();
        $bytes_hr = $bw_cache_obj->get_user_bytes_as_hash(
            ( map { ( $_ => $opts{$_} ) } qw( month year ) ),
            users => [ $opts{'username'} ],
        );
    }
    catch {
        warn $_ if !try { $_->isa('Cpanel::Exception::Database::DatabaseCreationInProgress') };
    };

    my $local = $bytes_hr->{ $opts{'username'} } || 0;

    require Cpanel::Bandwidth::Remote;
    my $remote = Cpanel::Bandwidth::Remote::fetch_remote_user_bandwidth(
        @opts{ 'username', 'month', 'year' },
    );

    return $local + $remote;
}

#Parameters (documented after-the-fact):
#
#   year        int
#   month       int, 1-12
#
#   showres     string, a specific reseller whose accounts to show
#               ignored if !Whostmgr::ACLS::hasroot()
#
#   search      Passed to Whostmgr::Accounts::List::search()
#   searchtype  (likewise)
#
sub _showbw {    ## no critic(Subroutines::ProhibitExcessComplexity)  -- Refactoring this function is a project, not a bug fix
    my %OPTS   = @_;
    my %CPCONF = Cpanel::Config::LoadCpConf::loadcpconf();

    Cpanel::AcctUtils::Load::loadaccountcache();

    my $current_month = Whostmgr::DateTime::getmonth();
    my $current_year  = Whostmgr::DateTime::getyear();
    my $month         = $OPTS{'month'} || $current_month;
    my $year          = $OPTS{'year'}  || $current_year;
    my $showres       = $OPTS{'showres'};
    if ( !Whostmgr::ACLS::hasroot() ) { $showres = ''; }

    $current_month += 0;
    $current_year  += 0;
    $month         += 0;
    $year          += 0;

    my %MAINDOMAINS;
    Cpanel::Config::LoadUserDomains::loadtrueuserdomains( \%MAINDOMAINS, 1 );
    my %USERS = map { $_ => 1 } Cpanel::Config::Users::getcpusers();
    my %OWNER;
    Cpanel::Config::LoadUserOwners::loadtrueuserowners( \%OWNER, 1, 1 );
    my %DOMAINLIST;
    Cpanel::Config::LoadUserDomains::loaduserdomains( \%DOMAINLIST, 0, 1 );
    my %BWLIMIT;
    Whostmgr::Bandwidth::loaduserbwlimits( \%BWLIMIT, 1, 1 );

    require Whostmgr::Accounts::List;
    my $search_results_ref;
    my $check_search = 0;
    if ( $OPTS{'search'} && $OPTS{'searchtype'} ) {
        $check_search       = 1;
        $search_results_ref = Whostmgr::Accounts::List::search(
            'owner_ref'      => \%OWNER,
            'truedomain_ref' => \%MAINDOMAINS,
            'search'         => $OPTS{'search'},
            'searchtype'     => $OPTS{'searchtype'}
        );
    }

    my %DEADDOMAINS;
    my %BW;

    my $reseller = $showres;
    if ( !$OPTS{'showres'} && Whostmgr::ACLS::hasroot() ) {
        $reseller = 'root';
    }
    if ( !Whostmgr::ACLS::hasroot() ) { $reseller = $ENV{'REMOTE_USER'}; }

    #In the interest of keeping the 11.50 SQLite bandwidth DB migration
    #smaller/safer, we actually iterate through the list of users more than
    #is strictly necessary.
    #TODO: Refactor this code and add tests.

    require Whostmgr::Accounts::Tiny;
    my $DUSERS_ref = Whostmgr::Accounts::Tiny::loaddeletedusers( $reseller, 1 );
    foreach my $duser ( keys %{$DUSERS_ref} ) {
        next if $check_search              && !exists $search_results_ref->{$duser};
        next if !Whostmgr::ACLS::hasroot() && !Whostmgr::AcctInfo::Owner::checkowner( $ENV{'REMOTE_USER'}, $duser );

        if ( $USERS{$duser} ) {
            $DUSERS_ref->{$duser}{'DELETED'} = 0;
            my @duser_keys;
            if ( defined $DUSERS_ref->{$duser}{'DNS'} && defined $BW{$duser}{ $DUSERS_ref->{$duser}{'DNS'} } ) {
                push @duser_keys, $BW{$duser}{ $DUSERS_ref->{$duser}{'DNS'} };
            }
            if ( ref $DUSERS_ref->{$duser}{'DNSLIST'} eq 'ARRAY' && scalar @{ $DUSERS_ref->{$duser}{'DNSLIST'} } ) {
                push @duser_keys, @{ $DUSERS_ref->{$duser}{'DNSLIST'} };
            }
            foreach my $key (@duser_keys) {
                next if ( $key =~ /^\s*$/ );
                $BW{$duser}{$key} ||= undef;
                $DEADDOMAINS{$key} = $duser;
            }
        }
        else {
            $OWNER{$duser}       = $DUSERS_ref->{$duser}{'OWNER'};
            $MAINDOMAINS{$duser} = $DUSERS_ref->{$duser}{'DNS'};
            $BWLIMIT{$duser}     = 'N/A';
        }
    }

    foreach my $user ( keys %USERS ) {
        next if $check_search              && !exists $search_results_ref->{$user};
        next if !Whostmgr::ACLS::hasroot() && !Whostmgr::AcctInfo::Owner::checkowner( $ENV{'REMOTE_USER'}, $user );

        foreach my $domain ( @{ $DOMAINLIST{$user} } ) {
            if ( !length $DEADDOMAINS{$domain} || $DEADDOMAINS{$domain} ne $user ) {
                if ( my $dead_domain_user = $DEADDOMAINS{$domain} ) {
                    delete $BW{$dead_domain_user}{$domain};    #if the domain we previously owned by another user and this user owners it now move the bandwidth usage to them
                }
                delete $DEADDOMAINS{$domain};
            }
            next if ( $BW{$user}{$domain} );
            $BW{$user}{$domain} ||= undef;
        }
    }

    Cpanel::LoadModule::load_perl_module('Cpanel::BandwidthDB::RootCache');
    my $bw_cache_obj = Cpanel::BandwidthDB::RootCache->new();

    my $users_limitation;
    if ( !Whostmgr::ACLS::hasroot() || $showres ) {
        $users_limitation = [ keys %BW ];
    }

    my $domains_bw_hr = $bw_cache_obj->get_user_domain_bytes_as_hash(
        year  => $year,
        month => $month,
        users => $users_limitation,
    );

    my $users_bw_hr = $bw_cache_obj->get_user_bytes_as_hash(
        year  => $year,
        month => $month,
        users => $users_limitation,
    );

    my $totalbw = Cpanel::ArrayFunc::sum( values %$users_bw_hr );
    my @BWUSAGE;
    my $RESref = Whostmgr::Resellers::List::list();

    require Cpanel::Bandwidth::Remote;
    my $all_remote_hr = Cpanel::Bandwidth::Remote::fetch_all_remote_users_domains_bandwidth( $month, $year );

    foreach my $user ( keys %BW ) {
        next if !$user || ( $showres && $OWNER{$user} ne $showres );
        next if !Whostmgr::ACLS::hasroot() && !Whostmgr::AcctInfo::Owner::checkowner( $ENV{'REMOTE_USER'}, $user );

        my $user_remote_hr = $all_remote_hr->{$user};

        my @BWU;
        foreach my $bwdomain ( keys %{ $BW{$user} } ) {
            my $usage = Whostmgr::Math::unsci( $domains_bw_hr->{$user}{$bwdomain} );

            if ($user_remote_hr) {
                $usage += $user_remote_hr->{'by_domain'}{$bwdomain} // 0;
            }

            push @BWU, {
                'domain'  => $bwdomain,
                'usage'   => $usage,
                'deleted' => ( $DEADDOMAINS{$bwdomain} ? 1 : 0 ),
            };
        }

        my $user_total_bytes = $users_bw_hr->{$user} // 0;

        if ($user_remote_hr) {
            my $user_total = $user_remote_hr->{'total'} // 0;

            $user_total_bytes += $user_total;
            $totalbw          += $user_total;
        }

        my %bwusage = (
            'user'       => $user,
            'totalbytes' => $user_total_bytes,
            'owner'      => ( $OWNER{$user} || 'root' ),
            'reseller'   => ( $RESref->{$user} ? '1' : 0 ),
            'limit'      => Whostmgr::Math::unsci( $BWLIMIT{$user} ),
            'maindomain' => $MAINDOMAINS{$user},
            'deleted'    => ( $DUSERS_ref->{$user}{'DELETED'} ? 1 : 0 ),
            'bwusage'    => \@BWU
        );

        # Whether a user/domain is being limited right now is only applicable to the current month.
        if ( $month == $current_month && $year == $current_year ) {

            # User will also work here but Apache mod_bwlimited checks the domain name so do the same to avoid discrepancies.
            $bwusage{'bwlimited'} = Cpanel::BandwidthMgr::user_or_domain_is_bwlimited( $MAINDOMAINS{$user} ) ? 1 : 0;
        }
        else {
            $bwusage{'bwlimited'} = $bwusage{'limit'} eq '0' || $bwusage{'limit'} eq 'unlimited' ? 0 : ( $bwusage{'totalbytes'} > $bwusage{'limit'} ? 1 : 0 );
        }
        push( @BWUSAGE, \%bwusage );
    }

    my @RSD;
    push( @RSD, { 'month' => $month, 'year' => $year, 'totalused' => Whostmgr::Math::unsci($totalbw), 'acct' => \@BWUSAGE, 'reseller' => $reseller } );

    return \@RSD;
}

sub setbwlimit {
    my %OPTS = @_;

    my $user    = $OPTS{'user'};
    my $bwlimit = $OPTS{'bwlimit'};

    if ( !Cpanel::AcctUtils::Account::accountexists($user) ) {
        return 0, "Invalid user ($user)";
    }

    my $cpuser_guard = Cpanel::Config::CpUserGuard->new($user);
    if ( !$cpuser_guard ) {
        return ( 0, "Invalid user ($user)" );
    }

    my $cpuser_data = $cpuser_guard->{'data'};
    my $domain      = $cpuser_data->{'DOMAIN'};

    # Check the form data
    if ( $bwlimit eq '0' || $bwlimit =~ /^\s*unlimited\s*$/ ) {
        $bwlimit = 0;
    }
    else {
        my $non_expon_int = Whostmgr::Math::get_non_exponential_int($bwlimit);

        # Note we disallow a decimal point, ditto for leading minus sign.
        if ( $non_expon_int !~ /^\d+$/ ) {
            return ( 0, "Sorry, the bandwidth value you specified, '$non_expon_int', is invalid.  Only non-negative, integral, simple numeric values or 'unlimited' are allowed." );
        }

        $bwlimit = $non_expon_int;
    }
    my $bytesbwlimit = int( $bwlimit * 1024 * 1024 );

    if ( !$user ) {
        return ( 0, "You must choose a user to change the bandwidth limit for." );
    }

    if (   !Whostmgr::ACLS::hasroot()
        && !Whostmgr::AcctInfo::Owner::checkowner( $ENV{'REMOTE_USER'}, $user ) ) {
        return ( 0, "You do not have permission to modify $user" );
    }

    if ( !Whostmgr::ACLS::hasroot() ) {
        my $reseller_limits = Whostmgr::Limits::Resellers::load_resellers_limits();
        my $resources       = $reseller_limits->{'limits'}->{'resources'};
        my $overselling     = $resources->{'overselling'}->{'type'}->{'bw'};

        if ( !$bwlimit && !( $resources->{'enabled'} && $overselling ) ) {
            return ( 0, "Sorry, you cannot have an account with an unlimited bandwidth limit.\n" );
        }

        my ( $limit_would_be_exceeded, $limit_message ) = Whostmgr::Limits::Exceed::would_exceed_limit( 'bw', { 'user' => $user, 'newlimit' => $bwlimit } );    #the user will be excluded from the calculation

        if ($limit_would_be_exceeded) { return ( 0, $limit_message ); }
    }
    my $bytes_used_this_month = get_acct_bw_usage_this_month($user);
    my %ret;
    $ret{'human_bwused'}  = ( !$bytes_used_this_month ? 'none'      : Cpanel::Math::_toHumanSize($bytes_used_this_month) );
    $ret{'human_bwlimit'} = ( !$bwlimit               ? 'unlimited' : Cpanel::Math::_toHumanSize($bytesbwlimit) );
    $ret{'bwlimit'}       = $bytesbwlimit;
    $ret{'unlimited'}     = ( !$bwlimit ? 1 : 0 );
    foreach my $dns ( @{ $cpuser_data->{'DOMAINS'} }, $cpuser_data->{'DOMAIN'} ) {
        push @{ $ret{'domains'} }, $dns;
    }

    if ( !$bwlimit || $bytesbwlimit > $bytes_used_this_month || -e '/var/cpanel/bwlimitcheck.disabled' ) {    #disable flag file
        Cpanel::BandwidthMgr::disablebwlimit( $user, $cpuser_data->{'DOMAIN'}, $bytesbwlimit, $bytes_used_this_month, 1, $cpuser_data->{'DOMAINS'} );
        $ret{'bwlimitenable'} = 0;
    }
    else {
        Cpanel::BandwidthMgr::enablebwlimit( $user, $cpuser_data->{'DOMAIN'}, $bytesbwlimit, $bytes_used_this_month, 1, $cpuser_data->{'DOMAINS'} );
        $ret{'bwlimitenable'} = 1;
    }

    # Save routine destroys the user's hash ref
    $cpuser_data->{'BWLIMIT'} = $bytesbwlimit || 'unlimited';
    $cpuser_guard->save();
    if ( !$OPTS{'no_updateuserdomains'} ) {
        Cpanel::Userdomains::updateuserdomains();    #update /etc/userbwlimits
    }

    my $set_to = $bwlimit ? $bwlimit : "unlimited";
    return ( 1, "Bandwidth Limit for $user has been set to $set_to megabytes", \%ret );
}

sub get_acct_bw_usage_this_month {
    my ($user) = @_;

    my $year  = Whostmgr::DateTime::getyear();
    my $month = Whostmgr::DateTime::getmonth();

    return getmonthbwusage(
        username => $user,
        month    => $month,
        year     => $year,
    );
}

1;
