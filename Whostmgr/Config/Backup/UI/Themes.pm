package Whostmgr::Config::Backup::UI::Themes;

# cpanel - Whostmgr/Config/Backup/UI/Themes.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Whostmgr::Config::Backup::Base );

use Whostmgr::Config::Themes ();

use constant version => '1.0.1';

sub _backup {
    my $self   = shift;
    my $parent = shift;

    my $files_to_copy = $parent->{'files_to_copy'}->{'cpanel::ui::themes'} = {};
    my $dirs_to_copy  = $parent->{'dirs_to_copy'}->{'cpanel::ui::themes'}  = {};

    foreach my $cfg_file ( keys %Whostmgr::Config::Themes::themes_files ) {
        my $special = $Whostmgr::Config::Themes::themes_files{$cfg_file}{'special'};
        if ( $special eq "dir" ) {
            my $archive_dir = $Whostmgr::Config::Themes::themes_files{$cfg_file}{'archive_dir'};
            $dirs_to_copy->{$cfg_file} = { "archive_dir" => $archive_dir };
        }
        elsif ( $special eq "present" ) {
            $files_to_copy->{$cfg_file} = { "dir" => "cpanel/ui/themes/config" };
        }
    }

    return ( 1, __PACKAGE__ . ": ok" );
}

sub query_module_info {
    my %output;
    $output{'THEMES'} = version();
    return \%output;
}

1;
