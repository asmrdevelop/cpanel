package Cpanel::Admin::Modules::Cpanel::feature;

# cpanel - Cpanel/Admin/Modules/Cpanel/feature.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Admin::Base );

our @ACTIONS = ( 'REBUILDFEATURECACHE', 'LOADFEATUREFILE' );

sub _actions { return @ACTIONS; }

sub REBUILDFEATURECACHE {
    my ($self) = @_;

    require Cpanel::Config::LoadCpUserFile;
    my $cpuser_ref = Cpanel::Config::LoadCpUserFile::load( $self->get_caller_username() );

    if ( !$cpuser_ref ) {
        die "Could not load cpanel users file for $self->get_caller_username(): $!";
    }

    require Cpanel::Features::Cpanel;
    my $feature_files_ref = Cpanel::Features::Cpanel::fetch_feature_file_list($cpuser_ref);
    require Cpanel::ConfigFiles;
    require Cpanel::Autodie;
    Cpanel::Autodie::mkdir( $Cpanel::ConfigFiles::features_cache_dir, 0755 ) if ( !-e $Cpanel::ConfigFiles::features_cache_dir );
    my ($feature_cache_file) = Cpanel::Features::Cpanel::calculate_cache_file_name_and_maxmtime($feature_files_ref);
    my $cache_ref = {};
    Cpanel::Features::Cpanel::populate( $feature_files_ref, {}, $cache_ref );
    require Cpanel::JSON;
    require Cpanel::FileUtils::Write;
    Cpanel::FileUtils::Write::overwrite( $feature_cache_file, Cpanel::JSON::Dump($cache_ref), 0644 );

    return 1;
}

sub LOADFEATUREFILE {
    my ( $self, $feature_file ) = @_;

    require Cpanel::Features::Load;
    die "$feature_file is not a valid feature list file." if !Cpanel::Features::Load::is_feature_list($feature_file);

    $feature_file = Cpanel::Features::Load::featurelist_file($feature_file);

    require Cpanel::Autodie;

    # This is only called if the perms on the file are incorrect, so lets fix it.
    Cpanel::Autodie::chmod( 0644, $feature_file );

    return Cpanel::Features::Load::load_feature_file($feature_file);
}

1;
