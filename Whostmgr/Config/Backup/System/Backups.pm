package Whostmgr::Config::Backup::System::Backups;

# cpanel - Whostmgr/Config/Backup/System/Backups.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Whostmgr::Config::Backup::Base );

use constant _ENOENT => 2;

use Cpanel::Backup::Transport ();

# These are not actively used, but are here for git greppers to know these
# affect us.
#
# use Cpanel::Transport::Files::Custom ();
# use Cpanel::Transport::Files::SFTP   ();

our $base_dir = '/var/cpanel/backups';

sub _backup {
    my $self   = shift;
    my $parent = shift;

    my $files_to_copy = $parent->{'files_to_copy'}->{'cpanel::system::backups'} = {};
    my $dirs_to_copy  = $parent->{'dirs_to_copy'}->{'cpanel::system::backups'}  = {};

    my $status    = 1;
    my $statusmsg = __PACKAGE__ . ': ok';

    # Back up main config file
    $files_to_copy->{ $base_dir . '/config' } = { 'dir' => 'cpanel/system/backups/' };

    # Back up each backup destination configuration
    if ( opendir( my $bu_dh, $base_dir ) ) {
        foreach my $file ( readdir($bu_dh) ) {

            # Copy over any backup destination configs
            if ( $file =~ m/\.backup_destination$/ ) {
                $files_to_copy->{ $base_dir . "/$file" } = { 'dir' => 'cpanel/system/backups/' };

                my $transport_cfg = Cpanel::Backup::Transport::_load_transport( $base_dir . "/$file" );
                if ( $transport_cfg->{'type'} eq "SFTP" ) {
                    if ( exists $transport_cfg->{'privatekey'} ) {
                        if ( -e $transport_cfg->{'privatekey'} ) {
                            $files_to_copy->{ $transport_cfg->{'privatekey'} } = { 'dir' => 'cpanel/system/backups/' . $file . "_plus" };
                        }
                    }
                }

                if ( $transport_cfg->{'type'} eq "CUSTOM" ) {

                    # we do not support this transport
                    delete $files_to_copy->{ $base_dir . "/$file" };

                    $status    = 2;
                    $statusmsg = __PACKAGE__ . ": Custom Transport not supported.";
                }
            }
        }
    }
    elsif ( $! != _ENOENT() ) {
        warn "opendir($base_dir): $!";
    }

    # Back up the "extras" directory of file backup lists
    $dirs_to_copy->{ $base_dir . '/extras' } = { 'archive_dir' => 'cpanel/system/backups/extras/' } if ( -d $base_dir . '/extras/' );

    return ( $status, $statusmsg );
}

1;
