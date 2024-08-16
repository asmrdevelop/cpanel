package Whostmgr::AcctInfo;

# cpanel - Whostmgr/AcctInfo.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Whostmgr::ACLS                 ();
use Whostmgr::AcctInfo::Owner      ();
use Cpanel::PwCache::Helpers       ();
use Cpanel::PwCache::Build         ();
use Cpanel::AcctUtils::Owner       ();
use Cpanel::Config::Users          ();
use Cpanel::Config::LoadUserOwners ();
use Cpanel::Config::LoadCpUserFile ();
use Cpanel::Config::HasCpUserFile  ();
use Whostmgr::AcctInfo::Plans      ();

*getowner      = *Cpanel::AcctUtils::Owner::getowner;
*checkowner    = *Whostmgr::AcctInfo::Owner::checkowner;
*loaduserplans = *Whostmgr::AcctInfo::Plans::loaduserplans;

#TESTS WHETHER "owner" IS THE USER, CONTROLLING RESELLER, OR ROOT, I.E. "HAS AUTHORITY" OVER THE ACCOUNT
sub hasauthority {
    my $owner = shift || return;
    my $user  = shift || return;

    return Whostmgr::ACLS::hasroot() || $owner eq $user || checkowner( $owner, $user ) ? 1 : 0;
}

sub acctlister {
    my $accttype = shift || return;
    my $owner    = shift;

    my %ACCTS;
    my $cpusers_ref = Cpanel::Config::Users::getcpusers();
    my $user_owner_hr;
    if ($owner) {
        $user_owner_hr = Cpanel::Config::LoadUserOwners::loadtrueuserowners( undef, 1, 1 );
    }
    my $userplan_ref = Whostmgr::AcctInfo::Plans::loaduserplans_include_undefined();
    foreach my $user ( @{$cpusers_ref} ) {
        if ($owner) { next if ( $user_owner_hr->{$user} ne $owner ); }
        if ( length $userplan_ref->{$user} ) {
            if ( $userplan_ref->{$user} eq $accttype ) {
                $ACCTS{$user} = 1;
            }
        }
        elsif ( Cpanel::Config::HasCpUserFile::has_cpuser_file($user) ) {
            my $cpuser_ref = Cpanel::Config::LoadCpUserFile::load($user);
            next if ( !scalar keys %{$cpuser_ref} );
            if ( $cpuser_ref->{'PLAN'} && $cpuser_ref->{'PLAN'} eq $accttype ) {
                $ACCTS{$user} = 1;
            }
        }
    }
    return wantarray ? %ACCTS : \%ACCTS;
}

sub acctamts {
    my $owner = shift || return;
    my %PLANS;
    my $userplan_ref  = Whostmgr::AcctInfo::Plans::loaduserplans_include_undefined();
    my $cpusers_ref   = Cpanel::Config::Users::getcpusers();
    my $user_owner_hr = Cpanel::Config::LoadUserOwners::loadtrueuserowners( undef, 1, 1 );

    foreach my $user ( @{$cpusers_ref} ) {
        next if !$user_owner_hr->{$user} || $user_owner_hr->{$user} ne $owner;
        if ( length $userplan_ref->{$user} ) {
            $PLANS{ $userplan_ref->{$user} }++;
        }
        elsif ( Cpanel::Config::HasCpUserFile::has_cpuser_file($user) ) {
            my $cpuser_ref = Cpanel::Config::LoadCpUserFile::load($user);
            if ( $cpuser_ref->{'PLAN'} ) {
                $PLANS{ $cpuser_ref->{'PLAN'} }++;
            }
        }
    }
    return wantarray ? %PLANS : \%PLANS;
}

#Parameters:
#   0) reseller (optional) - If given, restrict results to the given reseller.
#Returns a hash (or, in scalar, a hashref) of:
#   user1 => owner1,
#   user2 => owner2,
#   ...
# TODO: Move to Whostmgr::AcctInfo::Get
sub get_accounts {
    my $reseller = shift;

    my $userowners_hr = Cpanel::Config::LoadUserOwners::loadtrueuserowners( undef, 1, 1 );
    if ( !defined $reseller || $reseller eq '' ) {
        return wantarray ? %{$userowners_hr} : $userowners_hr;
    }
    else {
        my %RESLIST =
          map { ( $userowners_hr->{$_} eq $reseller ) ? ( $_ => $userowners_hr->{$_} ) : () } keys %{$userowners_hr};
        return wantarray ? %RESLIST : \%RESLIST;
    }
}

# TODO: Move to Whostmgr::AcctInfo::Get
#Same as get_accounts, but bails out if not given a reseller.
sub getaccts {
    my ($reseller) = @_;

    if ( !$reseller ) {
        return if wantarray;
        return wantarray ? () : {};
    }

    return get_accounts(@_);
}

sub suspendedlist {

    # PwCache was originally removed because we didn't have a way to
    # populate the password field
    # since all calls were the old Cpanel::PwCache::Build::init_passwdless_pwcache();
    # http://bugzilla.cpanel.net/show_bug.cgi?id=5755
    # since we now have Cpanel::PwCache::Build::init_pwcache(); this is no longer a
    # problem and pwcache can be used again for a major speedup in the whm reseller interface
    Cpanel::PwCache::Helpers::no_uid_cache();    #uid cache only needed if we are going to make lots of getpwuid calls

    if ( Cpanel::PwCache::Build::pwcache_is_initted() != 2 ) { Cpanel::PwCache::Build::init_pwcache(); }    # we need to look at the password hashes

    my $pwcache_ref = Cpanel::PwCache::Build::fetch_pwcache();

    my %SUS = map { $_->[0] => 1 } grep { ( $_->[1] =~ tr/\*// || $_->[1] =~ /^\!/ ) ? 1 : 0 } @{$pwcache_ref};

    return wantarray ? %SUS : \%SUS;
}

1;
