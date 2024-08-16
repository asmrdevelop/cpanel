package Whostmgr::Config::Restore::UI::Themes;

# cpanel - Whostmgr/Config/Restore/UI/Themes.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Whostmgr::Config::Restore::Base );

use Whostmgr::Config::Themes ();

use constant _version => '1.0.0';

sub _restore {
    my $self   = shift;
    my $parent = shift;

    my $backup_path = $parent->{'backup_path'};
    return ( 0, "Backup Path must be an absolute path" ) if ( $backup_path !~ /^\// );

    return ( 0, "version file missing from backup" ) if !-e "$backup_path/cpanel/ui/themes/version";

    foreach my $cfg_file ( keys %Whostmgr::Config::Themes::themes_files ) {
        my $special = $Whostmgr::Config::Themes::themes_files{$cfg_file}{'special'};

        if ( $special eq "dir" ) {
            my $archive_dir = $Whostmgr::Config::Themes::themes_files{$cfg_file}{'archive_dir'};
            $parent->{'dirs_to_copy'}->{$cfg_file} = { 'archive_dir' => $archive_dir };
            next;
        }

        my $file     = $cfg_file;
        my @fullpath = split( /\//, $file );
        my $basefile = $fullpath[-1];
        pop @fullpath;
        my $dir = join( '/', @fullpath );

        if ( $Whostmgr::Config::Themes::themes_files{$file}->{'special'} eq "present" ) {
            $parent->{'files_to_copy'}->{"$backup_path/cpanel/ui/themes/config/$basefile"} = { 'dir' => $dir, "file" => "$basefile" };

            if ( !-e "$backup_path/cpanel/ui/themes/config/$basefile" ) {
                $parent->{'files_to_copy'}->{"$backup_path/cpanel/ui/themes/config/$basefile"}->{'delete'} = 1;
            }
        }
    }

    return ( 1, __PACKAGE__ . ": ok", { 'version' => $self->_version() } );
}

1;
