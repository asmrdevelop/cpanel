package Cpanel::Features::Lists;

# cpanel - Cpanel/Features/Lists.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Features::Load ();

our $VERSION = '0.0.4';

our ( $feature_desc_dir, $feature_list_dir );

$feature_desc_dir = '/usr/local/cpanel/whostmgr';

BEGIN {
    $feature_desc_dir = '/usr/local/cpanel/whostmgr';
    *feature_list_dir = *Cpanel::Features::Load::feature_list_dir;
}

sub ensure_featurelist_dir {
    if ( !-d $feature_list_dir ) {
        mkdir( $feature_list_dir, 0755 )
          or die "Unable to create feature dir '$feature_list_dir': $!\n";
    }
    return;
}

#
# Implementation: We are checking the feature directory for files that contain
# feature lists. We are also ignoring any files that start with a '.' or end
# with '.cpaddons'.
sub get_feature_lists {
    my ($has_root) = @_;

    ensure_featurelist_dir();

    opendir( my $dir, $feature_list_dir )
      or die "Unable to open feature dir '$feature_list_dir': $!\n";
    my @FF = readdir($dir);
    closedir($dir);

    @FF = grep( !m{ \A [.] | [.]cpaddons \z}xms, @FF );

    if ($has_root) {
        my ( $hasdefault, $hasdisabled, $hasmailonly ) = ( 0, 0, 0 );
        foreach my $fet (@FF) {
            $hasdefault  = 1 if $fet eq 'default';
            $hasdisabled = 1 if $fet eq 'disabled';
            $hasmailonly = 1 if $fet eq 'Mail Only';
        }
        push @FF, 'default'   unless $hasdefault;
        push @FF, 'disabled'  unless $hasdisabled;
        push @FF, 'Mail Only' unless $hasmailonly;
    }
    my @list = sort(@FF);
    return @list;
}

sub get_user_feature_lists {
    my ( $user, $has_root ) = @_;

    my @features = get_feature_lists($has_root);
    return @features if $has_root;

    return grep { /^${user}_/ } @features;
}

sub get_user_and_global_feature_lists {
    my ( $user, $has_root ) = @_;

    my @features = get_feature_lists($has_root);
    return @features if $has_root;

    return grep { !/_/ || /^${user}_/ } @features;
}

1;
