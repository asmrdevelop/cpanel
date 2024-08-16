package Cpanel::Locale::Utils::Custom;

# cpanel - Cpanel/Locale/Utils/Custom.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::DataStore            ();
use Cpanel::FileUtils::Dir       ();
use Cpanel::Locale::Utils        ();
use Cpanel::Locale::Utils::Paths ();
use Cpanel::SafeDir::MK          ();

=head1 METHODS

=cut

sub clone_locale {

    # TODO:
    #   cp yaml
    #   cp pm
    #   modify NS in pm
    #   build db
}

sub update_key {
    my ( $key, $val, $locale, $theme, $force ) = @_;

    if ( $key eq '__FORENSIC' || $key eq 'charset' ) {
        return;
    }

    my ( $yaml_path, $cdb_path ) = get_locale_yaml_and_cdb_paths( $locale, $theme, $force ) or return;

    if ( my $hr = $force ? Cpanel::DataStore::fetch_ref($yaml_path) : Cpanel::DataStore::load_ref( $yaml_path, {} ) ) {
        $hr->{$key} = $val;
        if ( Cpanel::DataStore::store_ref( $yaml_path, $hr ) ) {
            my %into_readonly;
            my $tie_obj = Cpanel::Locale::Utils::get_readonly_tie( $cdb_path, \%into_readonly );
            my %into    = %into_readonly;                                                          #make a copy;
            undef $tie_obj;
            untie(%into_readonly);
            $into{$key} = $val;
            return Cpanel::Locale::Utils::create_cdb( $cdb_path, \%into );
        }
        else {

            # YAML write failed
            return;
        }
    }
    else {

        # YAML read failed
        return;
    }
}

sub del_key {
    my ( $key, $locale, $theme, $force ) = @_;

    my ( $yaml_path, $cdb_path ) = get_locale_yaml_and_cdb_paths( $locale, $theme, $force ) or return;

    if ( my $hr = $force ? Cpanel::DataStore::fetch_ref($yaml_path) : Cpanel::DataStore::load_ref($yaml_path) ) {
        delete $hr->{$key};
        if ( Cpanel::DataStore::store_ref( $yaml_path, $hr ) ) {
            my %into_readonly;
            my $tie_obj = Cpanel::Locale::Utils::get_readonly_tie( $cdb_path, \%into_readonly );
            my %into    = %into_readonly;                                                          #make a copy;
            undef $tie_obj;
            untie(%into_readonly);
            delete $into{$key};
            return Cpanel::Locale::Utils::create_cdb( $cdb_path, \%into );
        }
        else {

            # YAML write failed
            return;
        }
    }
    else {

        # YAML read failed
        return;
    }
}

sub get_locale_yaml_and_cdb_paths {
    my ( $locale, $theme, $force ) = @_;
    $force ||= 0;
    $theme ||= '';

    return if $locale =~ m{\W};
    return if $theme  =~ m{[/.]};

    my $yaml_path = Cpanel::Locale::Utils::Paths::get_locale_yaml_local_root();
    my $cdb_path  = Cpanel::Locale::Utils::Paths::get_locale_database_root();

    if ($theme) {

        # TODO: verify the compiler uses these YAML files and turns them into the CDB files
        # $yaml_path .= "/themes/$theme/$locale.yaml";
        $yaml_path = "/usr/local/cpanel/base/frontend/$theme/locale/$locale.yaml.local";
        $cdb_path .= "/themes/$theme/$locale.cdb";
    }
    else {

        # TODO: verify the compiler uses these YAML files and turns them into the CDB files
        $yaml_path .= "/$locale.yaml";
        $cdb_path  .= "/$locale.cdb";
    }
    return if !$force && !-e $yaml_path;

    for my $file ( $yaml_path, $cdb_path ) {
        my $path = reverse( ( ( reverse( split( '/', reverse($file), 2 ) ) ) )[0] );
        next if !$path || $path eq $file;
        Cpanel::SafeDir::MK::safemkdir($path);
    }

    return ( $yaml_path, $cdb_path );
}

=head2 get_custom_locales

List custom locales that have been installed.

=head3 Returns

Reference to an array of custom locales.

=cut

sub get_custom_locales {
    my $yaml_path = Cpanel::Locale::Utils::Paths::get_locale_yaml_local_root();
    my $nodes_ar  = Cpanel::FileUtils::Dir::get_directory_nodes_if_exists($yaml_path);
    $nodes_ar ||= [];

    my @custom_locales = ();

    foreach my $f ( @{$nodes_ar} ) {
        if ( $f =~ qr{^([0-9a-z_]+)\.yaml$} && -f $yaml_path . '/' . $f ) {
            push @custom_locales, $1;
        }
    }

    return [ sort @custom_locales ];
}

1;
