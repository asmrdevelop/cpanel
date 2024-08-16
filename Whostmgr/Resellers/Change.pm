package Whostmgr::Resellers::Change;

# cpanel - Whostmgr/Resellers/Change.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::AcctUtils::Owner         ();
use Cpanel::AcctUtils::AccountingLog ();
use Cpanel::PwCache::Helpers         ();
use Cpanel::PwCache::Build           ();
use Cpanel::Config::LoadUserOwners   ();
use Cpanel::Config::CpUserGuard      ();
use Cpanel::Config::userdata::Guard  ();
use Cpanel::Config::userdata::Load   ();
use Cpanel::Config::WebVhosts        ();
use Cpanel::Userdomains              ();
use Cpanel::Debug                    ();

#change_users_owners( 'nick', 'piggle' );
#change_users_owners( 'piggle', 'nick' );

sub change_users_owners {
    my ( $oldowner, $newowner ) = @_;
    my $owners          = Cpanel::Config::LoadUserOwners::loadtrueuserowners();
    my $users_to_change = $owners->{$oldowner};
    if ( $users_to_change && @{$users_to_change} ) {
        my $number_of_users_to_change = scalar @{$users_to_change};
        if ( $number_of_users_to_change > 3 ) {
            Cpanel::PwCache::Helpers::no_uid_cache();    #uid cache only needed if we are going to make lots of getpwuid calls
            Cpanel::PwCache::Build::init_passwdless_pwcache();
        }

        foreach my $user ( @{$users_to_change} ) {
            my $cpuser = Cpanel::Config::CpUserGuard->new($user);
            Cpanel::AcctUtils::AccountingLog::append_entry( 'CHANGEOWNER', [ $cpuser->{'data'}->{'DOMAIN'} // '', $user, $oldowner, $newowner ] );

            if ($cpuser) {
                $cpuser->{'data'}->{'OWNER'} = $newowner;
                $cpuser->save();
            }
            else {
                Cpanel::Debug::log_warn("Could not update user file for '$user'");
            }

            my $vh_conf = Cpanel::Config::WebVhosts->load($user);

            foreach my $vhname ( $vh_conf->main_domain(), $vh_conf->subdomains() ) {

                if ( my $guard = Cpanel::Config::userdata::Guard->new( $user, $vhname ) ) {
                    my $hr = $guard->data();
                    $hr->{'owner'} = $newowner;
                    $guard->save();
                }
                else {
                    Cpanel::Debug::log_warn("Could not update userdata file '$vhname' for '$user'");
                }

                #NB: For quite a while the SSL userdata was not updated here.
                #Maybe it’s not actually referenced? It seems to duplicate
                #information that’s in the cpuser file already.
                next if !Cpanel::Config::userdata::Load::user_has_ssl_domain( $user, $vhname );

                if ( my $guard = Cpanel::Config::userdata::Guard->new_ssl( $user, $vhname ) ) {
                    my $hr = $guard->data();
                    $hr->{'owner'} = $newowner;
                    $guard->save();
                }
                else {
                    Cpanel::Debug::log_warn("Could not update SSL userdata file '$vhname' for '$user'");
                }
            }
        }
        require Cpanel::Config::userdata::UpdateCache;
        Cpanel::Config::userdata::UpdateCache::update( @{$users_to_change} );
        Cpanel::Userdomains::updateuserdomains();

        # This updates the in memory cache of trueuserowners
        Cpanel::AcctUtils::Owner::build_trueuserowners_cache();
    }

    return ( 1, 'Users updated' );
}

1;
