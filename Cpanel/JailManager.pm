package Cpanel::JailManager;

# cpanel - Cpanel/JailManager.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::ConfigFiles             ();
use Cpanel::PwCache::Helpers        ();
use Cpanel::PwCache::Build          ();
use Cpanel::PwCache                 ();
use Cpanel::PwCache                 ();
use Cpanel::Filesys::Virtfs         ();
use Cpanel::Filesys::Virtfs::Setup  ();
use Cpanel::Config::LoadUserDomains ();
use Cpanel::CloudLinux::CageFS      ();

our $VERSION         = 1.6;
our $USERS_PER_BATCH = 256;

sub new {
    my ( $class, %OPTS ) = @_;

    my $self = { 'log_func' => $OPTS{'log_func'} };

    bless $self, $class;

    return $self;
}

sub update {
    my ($self) = @_;

    Cpanel::PwCache::Build::init_passwdless_pwcache();
    Cpanel::PwCache::Helpers::no_uid_cache();    #uid cache only needed if we are going to make lots of getpwuid calls
    my $pwcache_ref = Cpanel::PwCache::Build::fetch_pwcache();

    my %fs_is_mounted;
    foreach my $mount ( Cpanel::Filesys::Virtfs::get_virtfs_mounts() ) {
        if ( $mount =~ m{virtfs/([^/]+)} ) {
            $fs_is_mounted{$1} = 1;
        }
    }

    my %user_has_cagefs = map { $_ => 1 } Cpanel::CloudLinux::CageFS::enabled_users();

    my $cpusers = scalar Cpanel::Config::LoadUserDomains::loaduserdomains();
    my ( @users_to_jailmount, @uids_to_setup_virtfs );
    foreach my $pwref ( grep { $cpusers->{ $_->[0] } } @$pwcache_ref ) {
        my ( $user, $useruid, $usergid, $homedir, $shell ) = ( (@$pwref)[ 0, 2, 3, 7, 8 ] );

        next unless $shell && $shell =~ m{(?:no|jail)shell};

        if ( $fs_is_mounted{$user} ) {
            if ( $user_has_cagefs{$user} ) {

                # Clean up these virtfs mounts if the user has CageFS enabled.
                Cpanel::Filesys::Virtfs::clean_user_virtfs($user);
                next;
            }
            my $last_update_time = ( stat("/home/virtfs/$user/checkvirtfs") )[7] || 0;

            my $localdomains_last_update_time = ( stat("/etc/localdomains") )[7]                                                        || 0;
            my $userdomains_last_update_time  = ( stat("/etc/userdomains") )[7]                                                         || 0;
            my $mailman_flag_update_time      = ( stat("/var/cpanel/conf/jail/flags/mount_usr_local_cpanel_3rdparty_mailman_suid") )[7] || 0;

            # If would be much more efficient if localdomains were in /etc/mail which is bind mounted

            my $cpusers_time = ( stat("$Cpanel::ConfigFiles::cpanel_users/$user") )[7] || 0;
            if ( $last_update_time > $cpusers_time && $last_update_time > $mailman_flag_update_time && $last_update_time > $userdomains_last_update_time && $last_update_time > $localdomains_last_update_time ) {
                next;
            }
        }

        # Do not set up new virtfs mounts if the user has CageFS enabled.
        next if $user_has_cagefs{$user};

        push @users_to_jailmount,   $user if !$fs_is_mounted{$user};
        push @uids_to_setup_virtfs, $useruid;

    }

    while ( my @user_batch = splice( @users_to_jailmount, 0, $USERS_PER_BATCH ) ) {
        $self->{'log_func'}->("Mounting jail for @user_batch");
        system '/usr/local/cpanel/bin/jailmount', @user_batch;
    }

    foreach my $uid (@uids_to_setup_virtfs) {
        Cpanel::Filesys::Virtfs::Setup->new($uid)->setup();
    }

    return 1;
}

sub update_user {
    my ( $self, $user, $useruid, $fs_is_mounted ) = @_;

    return 1 if Cpanel::CloudLinux::CageFS::is_enabled_for_user($user);

    $useruid ||= ( Cpanel::PwCache::getpwnam($user) )[2];

    system '/usr/local/cpanel/bin/jailmount', $user if !$fs_is_mounted;

    return Cpanel::Filesys::Virtfs::Setup->new($useruid)->setup();
}

1;
