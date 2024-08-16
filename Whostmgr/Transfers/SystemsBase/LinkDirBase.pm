package Whostmgr::Transfers::SystemsBase::LinkDirBase;

# cpanel - Whostmgr/Transfers/SystemsBase/LinkDirBase.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Config::LoadWwwAcctConf ();

use base qw(
  Whostmgr::Transfers::Systems
);

my @INVALID_DIR_PREFIXES = (
    qw(
      /backup
      /bin
      /boot
      /cgroup
      /cpbackup
      /dev
      /etc
      /lib
      /lib64
      /media
      /mnt
      /proc
      /root
      /sbin
      /selinux
      /srv
      /sys
      /tmp
      /usr/bin
      /usr/etc
      /usr/games
      /usr/include
      /usr/lib
      /usr/lib64
      /usr/libexec
      /usr/local
      /usr/man
      /usr/sbin
      /usr/share
      /usr/src
      /var
    )
);

my @WHITELIST_DIR_PREFIXES = (
    qw(
      /var/www
    )
);

sub is_valid_path_for_old_dir_symlink_for_uid {
    my ( $self, $path, $uid ) = @_;

    my $whitelisted = 0;
    foreach my $whitelist_path (@WHITELIST_DIR_PREFIXES) {
        if ( $path eq $whitelist_path || $path =~ m{\A\Q$whitelist_path\E\/} ) {
            $whitelisted = 1;
        }

    }

    if ( !$whitelisted ) {
        foreach my $invalid_path (@INVALID_DIR_PREFIXES) {
            if ( $path eq $invalid_path || $path =~ m{\A\Q$invalid_path\E\/} ) {
                return 0;
            }
        }
    }

    # Now exclude any paths owned by another user
    my @PARTS     = split( m{/+}, $path );
    my @WALK_PATH = ();
    my $part;
    while ( defined( $part = shift @PARTS ) ) {
        push @WALK_PATH, $part;
        my $path_part = join( '/', @WALK_PATH ) || '/';

        my $path_uid = ( stat($path_part) )[4];

        last if !defined $path_uid;

        if ( $path_uid != 0 && $path_uid != $uid ) {
            return 0;
        }
    }

    return 1 if $self->{'_utils'}->is_unrestricted_restore();

    my $homedir    = $self->{'_utils'}->homedir();
    my $abshomedir = Cwd::abs_path( $self->{'_utils'}->homedir() );
    for my $basedir ( $homedir, $abshomedir ) {
        return 1 if $path =~ m{\A$basedir/};
    }

    my $wwwacctconf = Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();
    my $homematch   = $wwwacctconf->{'HOMEMATCH'};

    return ( !length($homematch) || ( $path =~ m{$homematch} ) ) ? 1 : 0;
}

1;
