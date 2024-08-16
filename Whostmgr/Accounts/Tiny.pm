package Whostmgr::Accounts::Tiny;

# cpanel - Whostmgr/Accounts/Tiny.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::AcctUtils::Account  ();
use Cpanel::PwCache::Build      ();
use Cpanel::Config::userdata    ();
use Cpanel::Config::CpUserGuard ();
use Cpanel::ConfigFiles         ();
use Cpanel::Debug               ();
use Cpanel::Domains             ();
use Cpanel::Userdomains         ();

sub _changeowner {
    my ( $user, $newowner ) = @_;

    my $usermap = {};
    if ( ref $user ) {
        unless ( Cpanel::PwCache::Build::pwcache_is_initted() ) { Cpanel::PwCache::Build::init_passwdless_pwcache(); }
        $usermap = $user;
    }
    else {
        $usermap->{$user} = $newowner;
    }

    open( my $acctlog_fh, '>>', $Cpanel::ConfigFiles::ACCOUNTING_LOG_FILE ) || do {
        my $error = "Could not write to $Cpanel::ConfigFiles::ACCOUNTING_LOG_FILE";
        Cpanel::Debug::log_warn($error);
        return wantarray ? ( 0, $error ) : 0;
    };
    chmod 0600, $Cpanel::ConfigFiles::ACCOUNTING_LOG_FILE;
    my $localtime = localtime();

    require Cpanel::Config::userdata;    # load on demand, its dependencies tree is huge CPANEL-5330

    foreach my $user ( keys %{$usermap} ) {
        my $newowner = $usermap->{$user};
        if ( !Cpanel::AcctUtils::Account::accountexists($user) ) {
            my $error = '_changeowner called for a user that does not exist.' . " ($user)";
            Cpanel::Debug::log_warn("$error");
            wantarray ? return ( 0, $error ) : return 0;
        }
        if ( !Cpanel::AcctUtils::Account::accountexists($newowner) ) {
            my $error = '_changeowner called for a new owner that does not exist.' . " ($newowner)";
            Cpanel::Debug::log_warn("$error");
            wantarray ? return ( 0, $error ) : return 0;
        }

        my $cpuser_guard = Cpanel::Config::CpUserGuard->new($user);
        my $old_owner    = $cpuser_guard->{'data'}->{'OWNER'} || 'root';
        my $domain       = $cpuser_guard->{'data'}->{'DOMAIN'};
        $cpuser_guard->{'data'}->{'OWNER'} = $newowner;
        $cpuser_guard->save();

        # Update virtualhost datastores
        # no_cache_update is set since we do this
        # after all users have been modified below
        Cpanel::Config::userdata::update_account_owner_data( { 'user' => $user, 'owner' => $newowner, 'no_cache_update' => 1 } );

        syswrite(
            $acctlog_fh,
            join(
                ':', map { defined $_ ? $_ : '' } $localtime, 'CHANGEOWNER', $ENV{'REMOTE_USER'}, $ENV{'USER'},
                $domain, $user, $old_owner, $newowner
              )
              . "\n"
        );
    }

    close($acctlog_fh);

    # Update /etc/trueuserowners
    Cpanel::Userdomains::updateuserdomains();

    # We only do this once instead of for each user when calling
    # update_account_owner_data
    # update /var/cpanel/userdata/$user/cache and /etc/userdatadomains
    require Cpanel::Config::userdata::UpdateCache;
    Cpanel::Config::userdata::UpdateCache::update( keys %{$usermap} );

    Cpanel::Domains::remove_deleteddomains_by_user($user);

    _ensure_vhost_includes_for_users( keys %{$usermap} );

    if ( $INC{'Cpanel/AcctUtils/Owner.pm'} ) {
        Cpanel::AcctUtils::Owner::clearcache();
    }

    return 1;
}

# Mocked in tests
sub _ensure_vhost_includes_for_users {
    my (@users) = @_;

    # Switch the includes to be for the correct owner -- will restart httpd only if needed
    require Cpanel::SafeRun::Object;
    my $run = Cpanel::SafeRun::Object->new( 'program' => '/usr/local/cpanel/scripts/ensure_vhost_includes', 'args' => [ ( map { '--user=' . $_ } @users ) ] );
    if ( $run->CHILD_ERROR() ) {
        warn "Error while running “/usr/local/cpanel/scripts/ensure_vhost_includes”: " . join( q< >, map { $run->$_() // () } qw( autopsy stdout stderr ) );
        return 0;
    }
    return 1;

}

sub loaddeletedusers {
    my $reseller        = shift;
    my $this_month_only = shift;
    my $deleted_db_ref  = Cpanel::Domains::load_deleted_db();

    if ( defined $reseller && $reseller eq 'root' ) {
        undef $reseller;
    }

    my %DUSER;
    my ( $currentmon, $currentyear ) = ( localtime( time() ) )[ 4, 5 ];
    foreach my $domain ( keys %{ $deleted_db_ref->{'data'} } ) {
        if ($this_month_only) {
            my $killtime = $deleted_db_ref->{'data'}->{$domain}->{'killtime'};
            my ( $Tmon, $Tyear ) = ( localtime($killtime) )[ 4, 5 ];
            next if ( $Tmon != $currentmon || $Tyear != $currentyear );
        }
        my $owner = $deleted_db_ref->{'data'}->{$domain}->{'reseller'};
        if ( $reseller && $reseller ne $owner ) {
            next;
        }
        my $user = $deleted_db_ref->{'data'}->{$domain}->{'user'};
        $DUSER{$user}{'OWNER'}   = $owner;
        $DUSER{$user}{'DELETED'} = 1;
        if ( $deleted_db_ref->{'data'}->{$domain}->{'is_main_domain'} ) {
            $DUSER{$user}{'DNS'} = $domain;
            if ( !$DUSER{$user}{'DNSLIST'} ) { $DUSER{$user}{'DNSLIST'} = []; }
        }
        else {
            push @{ $DUSER{$user}{'DNSLIST'} }, $domain;
        }
    }

    return \%DUSER;
}

1;
