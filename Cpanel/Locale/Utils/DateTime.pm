package Cpanel::Locale::Utils::DateTime;

# cpanel - Cpanel/Locale/Utils/DateTime.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#

use strict;
use Cpanel::LoadModule ();
use Cpanel::Locale     ();

# This modules are dynamiclly loaded and hidden from perlcc
our $ENCODE_MODULE          = 'Encode';
our $DATETIME_MODULE        = 'DateTime';
our $DATETIME_LOCALE_MODULE = 'DateTime::Locale';
my %known_ids = ();

sub datetime {
    my ( $lh, $epoch, $format, $timezone ) = @_;

    if ( $epoch && ref $epoch eq 'ARRAY' ) {
        $epoch = $epoch->[0];
    }
    elsif ( !$epoch ) {
        $epoch = time;
    }
    $format ||= 'date_format_long';

    my $encoding = $lh->encoding();

    #DateTime is slow and big. Only use it when needed.
    if ( _can_use_cpanel_date_format( $encoding, $timezone ) ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Date::Format');
        return Cpanel::Date::Format::translate_for_locale( $epoch, $format, $lh->language_tag() );
    }

    my $locale = _get_best_locale_for_datetime_obj( $lh->language_tag() );
    return _get_formatted_datetime( $locale, $encoding, $format, $epoch, $timezone );
}

sub _can_use_cpanel_date_format {
    my ( $encoding, $timezone ) = @_;

    #We should never output in non-UTF8 (for the forseeable future, at least),
    #but let’s be safe.
    return ( $encoding eq 'utf-8' ) && ( !$timezone || $timezone eq 'UTC' );
}

sub get_lookup_hash_of_multi_epoch_datetime {
    my ( $lh, $epochs_ar, $format, $timezone ) = @_;

    $format ||= 'date_format_long';
    my %lookups;

    my $encoding = $lh->encoding();

    my $can_use_cpanel_date_format = _can_use_cpanel_date_format( $encoding, $timezone );
    my $locale;

    if ($can_use_cpanel_date_format) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Date::Format');
        $locale = $lh->language_tag();
    }
    else {
        $locale = _get_best_locale_for_datetime_obj( $lh->language_tag() );
    }

    foreach my $epoch ( @{$epochs_ar} ) {
        $lookups{$epoch} ||= do {
            if ($can_use_cpanel_date_format) {
                Cpanel::Date::Format::translate_for_locale( $epoch, $format, $locale );
            }
            else {
                _get_formatted_datetime( $locale, $encoding, $format, $epoch, $timezone );
            }
        };
    }
    return \%lookups;
}

sub _get_formatted_datetime {
    my ( $locale, $encoding, $format, $epoch, $timezone ) = @_;

    if ( !$timezone ) {
        $timezone = 'UTC';
    }
    elsif ( $timezone !~ m{^[\.0-9A-Za-z\/_\+\-]+$} ) {
        die "Invalid timezone “$timezone”";
    }

    my $datetime_obj = $DATETIME_MODULE->from_epoch( 'epoch' => $epoch, 'locale' => $locale, 'time_zone' => $timezone );

    # _format$ == strftime which is deprectaed in DateTime::Locale v 0.44 in favor od CLDR
    if ( $format && $format !~ m{_format$} && $datetime_obj->{'locale'}->can($format) ) {
        return $ENCODE_MODULE->can('encode')->( $encoding, $datetime_obj->format_cldr( $datetime_obj->{'locale'}->$format ) );
    }

    die 'Invalid datetime format: ' . $format;
}

# This function implement dynamic loading of locales
# into DateTime.  By default DateTime loads the entire
# locale catalog which is very slow.  This ensures that
# only english is loaded until another locale is required
sub _get_best_locale_for_datetime_obj {
    my ($language_tag) = @_;
    my ( $fallback, $locale ) = _get_fallback_locale($language_tag);

    Cpanel::LoadModule::load_perl_module($ENCODE_MODULE) if !$INC{'Encode.pm'};
    Cpanel::LoadModule::load_perl_module($DATETIME_MODULE);

    foreach my $try_locale ( $locale, $fallback, 'en_US', 'en' ) {
        next               if !$try_locale;
        return $try_locale if $known_ids{$try_locale} || $Cpanel::Locale::known_locales_character_orientation{$try_locale};
        if ( eval { $DATETIME_MODULE->load($try_locale) } ) {
            $known_ids{$try_locale} = 1;
            return $try_locale;
        }
    }

    die "Could not locale any working DateTime locale";
}

sub _get_fallback_locale {
    my ($locale) = @_;
    my $fallback;
    if ( substr( $locale, 0, 2 ) eq 'i_' ) {
        require Cpanel::Locale::Utils::Paths;
        my $dir = Cpanel::Locale::Utils::Paths::get_i_locales_config_path();
        if ( -e "$dir/$locale.yaml" ) {
            require Cpanel::DataStore;
            my $hr = Cpanel::DataStore::fetch_ref("$dir/$locale.yaml");
            if ( exists $hr->{'fallback_locale'} && $hr->{'fallback_locale'} ) {
                $fallback = $hr->{'fallback_locale'};
            }
        }
    }
    else {
        # This emulates somewhat the aliasing that is being removed below.
        my ( $pre, $pst ) = split( /[\_\-]/, $locale, 2 );
        if ($pst) {
            $fallback = $pre;
            $locale   = $pre . '_' . uc($pst);
        }
    }
    $fallback ||= 'en';

    return ( $fallback, $locale );
}

1;
