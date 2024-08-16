package Whostmgr::Plugins;

# cpanel - Whostmgr/Plugins.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::CachedDataStore   ();
use Cpanel::AppConfig         ();
use Cpanel::StringFunc::Group ();
use Whostmgr::ACLS            ();

my $_plugins_cache;
my %mtimes;

#for testing
sub _reset_plugins_cache { undef $_plugins_cache; return }

sub third_party_plugin_directory { return '/usr/local/cpanel/Whostmgr/Thirdparty'; }
sub cgi_plugin_directory         { return '/usr/local/cpanel/whostmgr/docroot/cgi'; }
sub cache_file_path              { return '/var/cpanel/pluginscache.yaml'; }

my $cache_version = 1.0;

sub plugins_data {
    return $_plugins_cache if $_plugins_cache;

    return $_plugins_cache if _check_cache();

    update_cache();

    return $_plugins_cache;
}

sub update_cache {
    my ( %addons, @files, $mtime );
    $mtime = ( stat( cgi_plugin_directory() ) )[9] || 0;
    if ( opendir my $dh, cgi_plugin_directory() ) {
        while ( my $filename = readdir $dh ) {

            # Only process files that look like they have a valid file extension
            next if ( $filename !~ m/^addon_.+\.[a-z0-9]{2,4}$/ );

            my $cur_file = cgi_plugin_directory() . "/" . $filename;

            my $cur_mtime = ( $mtimes{$cur_file} ||= ( stat($cur_file) )[9] );
            if ( $cur_mtime > $mtime ) { $mtime = $cur_mtime }

            my $addons_ref = _process_plugin_file( $cur_file, \@files );

            if ($addons_ref) {
                $addons_ref->{'cgi'} = $filename;
                $addons{ $addons_ref->{'uniquekey'} } = $addons_ref;
            }
        }

        closedir $dh;
    }

    #same as above, but filtering for ".pm" files
    my $dir_mtime = ( stat( third_party_plugin_directory() ) )[9] || 0;
    if ( $dir_mtime > $mtime ) { $mtime = $dir_mtime }
    if ( opendir my $dh, third_party_plugin_directory() ) {
        while ( my $filename = readdir $dh ) {
            next if $filename !~ m{\.pm\z};

            my $cur_file  = third_party_plugin_directory() . "/" . $filename;
            my $cur_mtime = ( $mtimes{$cur_file} ||= ( stat($cur_file) )[9] );
            if ( $cur_mtime > $mtime ) { $mtime = $cur_mtime }

            my $addons_ref = _process_plugin_file( $cur_file, \@files );

            $addons{ $addons_ref->{'uniquekey'} } = $addons_ref if $addons_ref;
        }
        close $dh;
    }

    # This resets Cpanel::AppConfig’s internal cache, which is needed,
    # e.g., in the case of register_appconfig where we will have already
    # cached the get_application_list() result in memory prior to having
    # installed the new plugin configuration. It means we’ll need to load
    # the application list again, but that shouldn’t matter since we’re
    # updating a cache anyway.
    Cpanel::AppConfig::remove_loaded_apps_from_list();

    my $appconfig_apps = Cpanel::AppConfig::get_application_list();

    foreach my $app ( grep { $_->{'entryurl'} } @{ $appconfig_apps->{'whostmgr'} } ) {
        my $slugified_text = Cpanel::StringFunc::Group::group_words( $app->{'displayname'} || $app->{'name'} );
        $addons{$slugified_text} = {
            'cgi'       => $app->{'entryurl'},
            'target'    => ( $app->{'target'}      || '_blank' ),
            'tagname'   => ( $app->{'tagname'}     || '' ),
            'showname'  => ( $app->{'displayname'} || $app->{'name'} ),
            'icon'      => ( $app->{'icon'}        || '' ),
            'acllist'   => ( $app->{'acls'}        || [] ),
            'uniquekey' => $slugified_text,
        };

    }

    my @addons = sort { $a->{'showname'} cmp $b->{'showname'} } values %addons;

    Cpanel::CachedDataStore::store_ref(
        cache_file_path(),
        {
            'addons'  => \@addons,
            'files'   => \@files,
            'mtime'   => $mtime,
            'version' => $cache_version,
        }
    );

    $_plugins_cache = _filter_addon_list( \@addons );

    return;
}

sub _process_plugin_file {
    my ( $cur_file, $files_ref ) = @_;

    my $addons_ref;
    if ( open my $fh, '<', $cur_file ) {
        while ( my $line = readline $fh ) {
            if ( $line =~ m{\A#WHMADDON:(.*)} ) {
                my ( $tagname, $showname, $icon ) = split /:/, $1;
                my @acllist;
                $line = readline($fh);
                if ( $line =~ m{\A#ACLS:(.*)} ) {
                    @acllist = split /,/, $1;
                }

                my $slugified_text = Cpanel::StringFunc::Group::group_words($showname);

                push @{$files_ref}, $cur_file;

                $addons_ref = {
                    'tagname'   => $tagname,
                    'showname'  => $showname,
                    'icon'      => $icon,
                    'acllist'   => \@acllist,
                    'target'    => '_blank',
                    'uniquekey' => $slugified_text
                };

                last;
            }
        }

        close $fh;
    }

    return $addons_ref;
}

sub _check_cache {
    return 0 unless -e cache_file_path();

    my $addons_cache_hr = Cpanel::CachedDataStore::loaddatastore( cache_file_path() );
    return 0 unless $addons_cache_hr && $addons_cache_hr->{data};

    $addons_cache_hr = $addons_cache_hr->{data};
    return 0 unless defined $addons_cache_hr->{'version'} && $addons_cache_hr->{'version'} == $cache_version;

    my @files_to_check = (
        third_party_plugin_directory(),
        cgi_plugin_directory(),
        @{ $addons_cache_hr->{'files'} }
    );

    my %missing_ok = ( third_party_plugin_directory() => 1 );

    my $cache_mtime    = $addons_cache_hr->{'mtime'};
    my $cache_is_valid = 1;
    foreach my $file (@files_to_check) {
        if ( my $fs_mtime = $mtimes{$file} = ( stat($file) )[9] ) {

            #if the file doesn't exist or has a newer mtime than the cache...
            if ( $fs_mtime > $cache_mtime ) {
                $cache_is_valid = 0;
                last;
            }
        }
        else {
            if ( !$missing_ok{$file} ) {
                $cache_is_valid = 0;
                last;
            }
        }
    }

    if ($cache_is_valid) {
        $_plugins_cache = _filter_addon_list( $addons_cache_hr->{'addons'} );
    }

    return $cache_is_valid;
}

sub _filter_addon_list {
    my $addons_ref = shift;
    my @filtered_list;
    foreach my $addon ( @{$addons_ref} ) {

        if ( !scalar @{ $addon->{'acllist'} } ) {
            push @filtered_list, $addon;
        }
        else {
            foreach my $acl ( @{ $addon->{'acllist'} } ) {
                if ( Whostmgr::ACLS::checkacl($acl) ) {
                    push @filtered_list, $addon;
                    last;
                }
            }
        }
    }
    return \@filtered_list;
}

1;
