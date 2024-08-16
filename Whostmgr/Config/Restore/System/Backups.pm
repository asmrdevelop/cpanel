package Whostmgr::Config::Restore::System::Backups;

# cpanel - Whostmgr/Config/Restore/System/Backups.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Whostmgr::Config::Restore::Base );

use constant _ENOENT => 2;

use Whostmgr::Config::BackupUtils ();
use Cpanel::Backup::Transport     ();

use constant _version => '1.0.0';

sub _restore {
    my $self   = shift;
    my $parent = shift;

    my $backup_path = $parent->{'backup_path'};
    return ( 0, "Backup Path must be an absolute path" ) if ( $backup_path !~ /^\// );

    # Restore main backups config file
    $parent->{'files_to_copy'}->{"$backup_path/cpanel/system/backups/config"} = { 'dir' => '/var/cpanel/backups/', 'file' => 'config' };

    # Restore each of the destination files
    if ( opendir( my $bu_dh, "$backup_path/cpanel/system/backups/" ) ) {
        foreach my $file ( readdir($bu_dh) ) {
            if ( $file =~ m/\.backup_destination$/ ) {
                my $full_path = "$backup_path/cpanel/system/backups/$file";

                $parent->{'files_to_copy'}->{$full_path} = { 'dir' => '/var/cpanel/backups/', 'file' => $file };

                my $transport_cfg = Cpanel::Backup::Transport::_load_transport($full_path);
                if ( $transport_cfg->{'type'} eq "SFTP" ) {
                    if ( exists $transport_cfg->{'privatekey'} ) {
                        my $parent_path = Whostmgr::Config::BackupUtils::get_parent_path( $transport_cfg->{'privatekey'}, 0 );
                        my $file_name   = Whostmgr::Config::BackupUtils::remove_base_path( $parent_path, $transport_cfg->{'privatekey'} );

                        $parent->{'files_to_copy'}->{"${full_path}_plus/$file_name"} = { 'dir' => $parent_path, 'file' => $file_name };
                    }
                }
            }
        }
        closedir($bu_dh);
    }
    else {
        print "Could not open dir $backup_path/cpanel/system/backups/ : $!\n";
    }

    # Restore each of the "extras" files for additional files to include with backups
    my $extras_path = "$backup_path/cpanel/system/backups/extras/";
    if ( opendir( my $extras_dh, $extras_path ) ) {
        foreach my $file ( readdir($extras_dh) ) {
            if ( $file !~ m/^\./ ) {
                $parent->{'files_to_copy'}->{"$backup_path/cpanel/system/backups/extras/$file"} = { 'dir' => '/var/cpanel/backups/extras/', 'file' => $file };
            }
        }
        closedir($extras_dh);
    }
    elsif ( $! != _ENOENT() ) {
        warn "opendir($extras_path): $!";
    }

    return ( 1, __PACKAGE__ . ": ok", { 'version' => $self->_version() } );
}

sub post_restore {
    unlink '/var/cpanel/backups/config.cache';
    return __PACKAGE__->SUPER::post_restore();
}

1;
