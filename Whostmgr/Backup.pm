package Whostmgr::Backup;

# cpanel - Whostmgr/Backup.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Config::Backup ();
use Cpanel::SysBackup      ();

*fetchbackupdir = *Cpanel::SysBackup::fetchbackupdir;

sub get_restore_types {
    my $backups_dir = Cpanel::SysBackup::fetchbackupdir() . '/cpbackup';
    my @types;
    if ( opendir my $dh, $backups_dir ) {
        @types = grep { !m{\.} } ( readdir $dh );
        closedir $dh;
    }
    return @types;
}

sub get_backed_up_users {
    my ($restore_type) = @_;
    $restore_type ||= 'daily';
    my @users;

    my %CONF        = Cpanel::Config::Backup::load();
    my $backups_dir = $CONF{'BACKUPDIR'} . "/cpbackup/$restore_type";
    my $inc_backups = $CONF{'BACKUPINC'} eq 'yes' ? 1 : 0;

    my @possible_backups;
    if ( opendir my $dh, $backups_dir ) {
        @possible_backups = readdir $dh;
        closedir $dh;
    }

    foreach my $file (@possible_backups) {
        if ($inc_backups) {
            if ( -d "$backups_dir/$file" && $file !~ m{\.tar(?:\.gz)?\z} && $file !~ m{\A(?:files|dirs|\.+)\z} && $file !~ m{\.\d+\z} ) {
                push @users, $file;
            }
        }
        elsif ( -f "$backups_dir/$file" && $file =~ m{\A(.*)\.tar(?:\.gz)?\z} ) {
            push @users, $1;
        }
    }

    return @users;
}

1;
