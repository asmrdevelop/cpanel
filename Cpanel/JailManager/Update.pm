package Cpanel::JailManager::Update;

# cpanel - Cpanel/JailManager/Update.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::PwCache::Build     ();
use Cpanel::PwCache            ();
use Cpanel::JailManager        ();
use Cpanel::Debug              ();
use Cpanel::Config::Users      ();
use Whostmgr::Cron             ();
use Cpanel::CloudLinux::CageFS ();

=pod

=head1 NAME

Cpanel::JailManager::Update

=head1 SYNOPSIS

  # All Users
  my $count = Cpanel::JailManager::Update::update_users_jail();

  # Just bob
  my $count = Cpanel::JailManager::Update::update_users_jail('bob');

=head2 update_users_jail( [USER] )

Rebuild or umount a users jail (virtfs)

=head3 Arguments

USER (optional) - The user to rebuild (or unmount)

=head3 Return Value

The number of users that update_users_jail successfully processed

=cut

#
# update_users_jail was relocated from
# scripts/update_users_jail
#
# update_users_jail will rebuild the virtfs
# and ensure that all the virtfs mounts are in
# place for the a given user.  If not user is passed
# it will rebuild all users.
#
# TODO: This function was merely relocated from
# scripts/update_users_jail.  In the future it should
# be broken into multiple functions.  The ApacheTasks
# queueprocd module and scripts/update_users_jail
# will need to call the new functions.
#
sub update_users_jail {
    my ($user) = @_;

    my @users    = $user ? ($user) : Cpanel::Config::Users::getcpusers();
    my $jail_mgr = Cpanel::JailManager->new( 'log_func' => \&Cpanel::Debug::log_warn );

    Cpanel::PwCache::Build::init_passwdless_pwcache() if !$user;
    my $processed       = 0;
    my %user_has_cagefs = map { $_ => 1 } Cpanel::CloudLinux::CageFS::enabled_users();
    foreach my $user (@users) {

        my @PW    = Cpanel::PwCache::getpwnam_noshadow($user);
        my $shell = $PW[8];

        next if !$shell;

        # If the user has CageFS enabled we should unmount their virtfs even if jail/noshell is in use.
        if ( $shell =~ m{(?:no|jail)shell} && !$user_has_cagefs{$user} ) {
            $jail_mgr->update_user($user);
        }
        else {
            require Cpanel::Filesys::Virtfs if !$INC{'Cpanel/Filesys/Virtfs.pm'};
            Cpanel::Filesys::Virtfs::clean_user_virtfs($user);
        }

        my ( $ok, $msg ) = Whostmgr::Cron::sync_user_cron_shell($user);
        warn "$msg\n" if !$ok;

        $processed++;
    }

    return $processed;
}

1;
