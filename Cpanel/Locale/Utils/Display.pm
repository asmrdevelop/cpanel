package Cpanel::Locale::Utils::Display;

# cpanel - Cpanel/Locale/Utils/Display.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use warnings;
use strict;
use Cpanel::Locale::Utils::Paths ();

sub get_locale_list {
    my ($lh) = @_;
    my @result = @{ $lh->{'_cached_get_locale_list'} ||= [ sort ( 'en', $lh->list_available_locales() ) ] };

    # Check to see if we want to allow snowmen to be displayed
    # If the file is not present, cull snowmen from the list (but only from this list)
    if ( !-e "/var/cpanel/enable_snowmen" ) {
        @result = grep { !/i_cpanel_snowmen/ } @result;
    }
    return @result;
}

sub get_non_existent_locale_list {
    my ( $lh, $loc_obj ) = @_;

    $loc_obj ||= $lh->get_locales_obj('en');
    my %have;
    @have{ get_locale_list($lh), 'en_us', 'i_default', 'und', 'zxx', 'mul', 'mis', 'art' } = ();
    return sort grep { !exists $have{$_} } $loc_obj->get_language_codes();
}

sub get_locale_menu_hashref {
    my ( $lh, $omit_current_locale, $native_only, $skip_locales ) = @_;

    $skip_locales ||= {};
    my %langs;
    my %dir;

    # since 'en' may not be listed due its alias/non-filesystem-ness we specifically add it here and sort the same way the method does
    my @langs = get_locale_list($lh);

    # We usually skip locales when we have already
    # called this function and have the return data
    # but want to add more locales at a later time
    my @wanted_langs = grep { !$skip_locales->{$_} } @langs;

    if ( !@wanted_langs ) {
        return ( {}, \@langs, {} );
    }

    my $func = $native_only ? 'lang_names_hashref_native_only' : 'lang_names_hashref';
    my ( $localized_name_for_tag, $native_name_for_tag, $direction_map ) = $lh->$func(@wanted_langs);
    my $current_tag = $lh->get_language_tag();
    $current_tag = 'en' if $current_tag eq 'en_us' || $current_tag eq 'i_default';

    my $i_locales_path = Cpanel::Locale::Utils::Paths::get_i_locales_config_path();
    if ($omit_current_locale) {
        delete $localized_name_for_tag->{$current_tag};
        delete $native_name_for_tag->{$current_tag};
        @langs = grep { $_ ne $current_tag } @langs;
    }

    foreach my $tag ( keys %{$localized_name_for_tag} ) {
        if ( index( $tag, 'i_' ) == 0 ) {
            require Cpanel::DataStore;
            my $i_conf = Cpanel::DataStore::fetch_ref("$i_locales_path/$tag.yaml");
            $langs{$tag} = exists $i_conf->{'display_name'} && defined $i_conf->{'display_name'} && $i_conf->{'display_name'} ne '' ? "$i_conf->{'display_name'} - $tag" : $tag;                    # slightly different format than real tags to visually indicate specialness
            $native_name_for_tag->{$tag} = $langs{$tag};

            if ( exists $i_conf->{'character_orientation'} ) {
                $dir{$tag} = $lh->get_html_dir_attr( $i_conf->{'character_orientation'} );
            }
            elsif ( exists $i_conf->{'fallback_locale'} && exists $direction_map->{ $i_conf->{'fallback_locale'} } ) {
                $dir{$tag} = $direction_map->{ $i_conf->{'fallback_locale'} };
            }

            next;
        }

        if ( exists $direction_map->{$tag} ) {
            $dir{$tag} = $lh->get_html_dir_attr( $direction_map->{$tag} );
        }

        next if $native_only;

        if ( $native_name_for_tag->{$tag} eq $localized_name_for_tag->{$tag} ) {
            if ( $tag eq $current_tag ) {
                $langs{$tag} = $native_name_for_tag->{$tag};
            }
            else {
                $langs{$tag} = "$localized_name_for_tag->{$tag} ($tag)";
            }
        }
        else {
            $langs{$tag} = "$localized_name_for_tag->{$tag} ($native_name_for_tag->{$tag})";
        }
    }

    if ($native_only) {
        return wantarray ? ( $native_name_for_tag, \@langs, \%dir ) : $native_name_for_tag;
    }

    return wantarray ? ( \%langs, \@langs, \%dir ) : \%langs;
}

sub get_non_existent_locale_menu_hashref {
    my $lh = shift;

    # Even though get_locales_obj() memoizes/caches/singletons itself we can still avoid a
    # method call if we already have the Locales object that belongs to the handle's locale.
    $lh->{'Locales.pm'}{'_main_'} ||= $lh->get_locales_obj();

    my %langs;
    my %dir;
    my @langs = get_non_existent_locale_list( $lh, $lh->{'Locales.pm'}{'_main_'} );

    my $wantarray = wantarray() ? 1 : 0;

    for my $code (@langs) {
        if ($wantarray) {
            if ( my $orient = $lh->{'Locales.pm'}{'_main_'}->get_character_orientation_from_code_fast($code) ) {
                $dir{$code} = $lh->get_html_dir_attr($orient);
            }
        }

        my $current = $lh->{'Locales.pm'}{'_main_'}->get_language_from_code( $code, 1 );
        my $native  = $lh->{'Locales.pm'}{'_main_'}->get_native_language_from_code( $code, 1 );
        $langs{$code} = $current eq $native ? "$current ($code)" : "$current ($native)";
    }

    return wantarray ? ( \%langs, \@langs, \%dir ) : \%langs;
}

sub in_translation_vetting_mode {
    return ( -e '/var/cpanel/translation_vetting_mode' ) ? 1 : 0;
}

1;
