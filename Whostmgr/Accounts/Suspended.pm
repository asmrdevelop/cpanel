package Whostmgr::Accounts::Suspended;

# cpanel - Whostmgr/Accounts/Suspended.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::LoadUserDomains ();
use Cpanel::Debug                   ();
use Cpanel::PwCache                 ();
use Cpanel::PwCache::Build          ();
use Cpanel::PwCache::Helpers        ();
use Cpanel::Config::LoadCpUserFile  ();
use Cpanel::FileUtils::Dir          ();

our $SUSPENDED_DIR = '/var/cpanel/suspended';
our $BANDWIDTH_DIR = '/var/cpanel/bwlimited';

sub getsuspendedlist {
    my ( $fetchtime, $check_users, $cpuser_data_by_user, $include_bandwidth_limited_users ) = @_;

    $cpuser_data_by_user ||= {};
    my $valid_users_ref = {};
    $include_bandwidth_limited_users //= 1;
    my ( %SUSPEND, %SUSREASON, %SUSTIME, %SUSLOCKED );

    # If $check_users is an hashref
    #
    if ( ref $check_users ) {

        #
        # If there are users in the check_users then use them
        # otherwise we load it from trueuser domains
        #
        if ( scalar keys %$check_users ) {
            $valid_users_ref = $check_users;
        }
        else {
            $valid_users_ref = Cpanel::Config::LoadUserDomains::loadtrueuserdomains( undef, 1 );
        }
    }
    elsif ($check_users) {

        #
        # If check_users is not a hashref and it is defined it is a single user
        #
        $valid_users_ref = { $check_users => 1 };
    }
    else {
        $valid_users_ref = Cpanel::Config::LoadUserDomains::loadtrueuserdomains( undef, 1 );
    }

    my @pwcache_list;
    if ( scalar keys %{$valid_users_ref} == 1 ) {
        my $single_user = ( keys %{$valid_users_ref} )[0];
        @pwcache_list = [ Cpanel::PwCache::getpwnam($single_user) ];
    }
    else {
        if ( Cpanel::PwCache::Build::pwcache_is_initted() != 2 ) {
            Cpanel::PwCache::Helpers::no_uid_cache();    #uid cache only needed if we are going to make lots of getpwuid calls
            Cpanel::PwCache::Build::init_pwcache();
        }    # we need to look at the password hashes
        my $pwcache_ref = Cpanel::PwCache::Build::fetch_pwcache();
        @pwcache_list = grep { exists $valid_users_ref->{ $_->[0] } } @{$pwcache_ref};
    }

    %SUSPEND = map { ( index( $_->[1], '!' ) == 0 || index( $_->[1], '*LOCKED*' ) > -1 ) ? ( $_->[0] => 1 ) : () } @pwcache_list;

    if ($include_bandwidth_limited_users) {
        get_bandwidth_suspended_users( \%SUSPEND, \%SUSREASON, $valid_users_ref );
    }

    my $loaded_suspended_files = 0;
    my %has_suspended_file;
    foreach my $user ( keys %SUSPEND ) {
        if ( !exists $SUSREASON{$user} ) {
            if ( !$loaded_suspended_files ) {

                # The $SUSPENDED_DIR may not exist until at least one user
                # has been suspended so we check before calling get_directory_nodes_if_exists
                # in order to avoid an exception for an expected condition.
                if ( -e $SUSPENDED_DIR ) {

                    # Its much cheaper to load the list of users that have files into memory
                    # once than stat every file in the directory since it will significantly
                    # reduce the number of syscalls when there are even just a few users.

                    my $nodes_ar = Cpanel::FileUtils::Dir::get_directory_nodes_if_exists($SUSPENDED_DIR);
                    if ($nodes_ar) {
                        %has_suspended_file = map { $_ => 1 } @$nodes_ar;
                    }
                }
                $loaded_suspended_files = 1;
            }

            if ( $has_suspended_file{$user} ) {
                if ( open( my $sr_fh, "<", "$SUSPENDED_DIR/$user" ) ) {
                    if ($fetchtime) { $SUSTIME{$user} = ( stat($sr_fh) )[9]; }
                    local ($/);

                    # An empty suspension reason has historically been allowed.
                    # In this case we set the reason to 'Unknown' for backwards
                    # compatibility.
                    $SUSREASON{$user} = readline($sr_fh) || 'Unknown';
                    close($sr_fh);
                }
                else {
                    Cpanel::Debug::log_warn("Failed to open($SUSPENDED_DIR/$user): $!");
                }
            }

            $SUSREASON{$user} ||= 'Unknown';

            if ( $fetchtime && !$SUSTIME{$user} ) {
                $cpuser_data_by_user->{$user} ||= Cpanel::Config::LoadCpUserFile::load($user);
                $SUSTIME{$user} = $cpuser_data_by_user->{$user}{'SUSPENDTIME'} || 0;
            }
        }
        $SUSLOCKED{$user} = is_locked($user) ? 1 : 0;
    }

    return ( \%SUSPEND, \%SUSREASON, \%SUSTIME, \%SUSLOCKED );
}

#locked = suspended by root, only root can re-enable
sub is_locked {
    my $user = shift;

    return ( -e "$SUSPENDED_DIR/$user.lock" );
}

sub get_bandwidth_suspended_users {
    my ( $suspended_users, $suspension_reasons, $valid_users_ref ) = @_;

    ## FIXME: bandwidth limited users are not really "suspended"; e.g. see whm's suspendlist
    if ( opendir( my $bwlimited_dir, $BANDWIDTH_DIR ) ) {
        foreach my $user ( grep ( !/^\./, readdir($bwlimited_dir) ) ) {
            next unless exists $valid_users_ref->{$user};
            ( $suspended_users->{$user}, $suspension_reasons->{$user} ) = ( 1, 'Bandwidth Limit Exceeded; Unsuspend by increasing bandwidth limit' );
        }
        closedir($bwlimited_dir);
    }
    return 1;
}

1;
