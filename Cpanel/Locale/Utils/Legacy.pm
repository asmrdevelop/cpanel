package Cpanel::Locale::Utils::Legacy;

# cpanel - Cpanel/Locale/Utils/Legacy.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Locale::Utils::Normalize ();
use Cpanel::Locale::Utils::Paths     ();

my %oldname_to_locale;
my $loc;

sub _load_oldnames {

    %oldname_to_locale = (
        'turkish'                   => 'tr',
        'traditional-chinese'       => 'zh',
        'thai'                      => 'th',
        'swedish'                   => 'sv',
        'spanish-utf8'              => 'es',
        'spanish'                   => 'es',
        'slovenian'                 => 'sl',
        'simplified-chinese'        => 'zh_cn',
        'russian'                   => 'ru',
        'romanian'                  => 'ro',
        'portuguese-utf8'           => 'pt',
        'portuguese'                => 'pt',
        'polish'                    => 'pl',
        'norwegian'                 => 'no',
        'korean'                    => 'ko',
        'japanese-shift_jis'        => 'ja',       # see Cpanel::Locale::Utils::MkDB::compile_single_legacy_from_legacy_system()
        'japanese-euc-jp'           => 'ja',       # see Cpanel::Locale::Utils::MkDB::compile_single_legacy_from_legacy_system()
        'japanese'                  => 'ja',       # see Cpanel::Locale::Utils::MkDB::compile_single_legacy_from_legacy_system()
        'spanish_latinamerica'      => 'es_419',
        'iberian_spanish'           => 'es_es',
        'italian'                   => 'it',
        'indonesian'                => 'id',
        'hungarian'                 => 'hu',
        'german-utf8'               => 'de',
        'german'                    => 'de',
        'french-utf8'               => 'fr',
        'french'                    => 'fr',
        'finnish'                   => 'fi',
        'english-utf8'              => 'en',
        'english'                   => 'en',
        'dutch-utf8'                => 'nl',
        'dutch'                     => 'nl',
        'chinese'                   => 'zh',
        'bulgarian'                 => 'bg',
        'brazilian-portuguese-utf8' => 'pt_br',
        'brazilian-portuguese'      => 'pt_br',
        'arabic'                    => 'ar',
    );

    {
        no warnings 'redefine';
        *_load_oldnames = sub { };
    }

    return;
}

sub get_legacy_to_locale_map {
    _load_oldnames();
    return \%oldname_to_locale;
}

sub get_legacy_list_from_locale {
    my ($locale) = @_;
    return         if !$locale;
    $locale = 'en' if $locale eq 'en_us' || $locale eq 'i_default';
    _load_oldnames();
    return grep { $oldname_to_locale{$_} eq $locale ? 1 : 0 } keys %oldname_to_locale;
}

sub get_best_guess_of_legacy_from_locale {
    my ( $locale, $always_return_useable ) = @_;
    return         if !$locale && !$always_return_useable;
    $locale = 'en' if $locale eq 'en_us' || $locale eq 'i_default';
    _load_oldnames();
    my @legacy_locale_matches = grep { $oldname_to_locale{$_} eq $locale ? 1 : 0 } keys %oldname_to_locale;
    return $legacy_locale_matches[0] if @legacy_locale_matches;
    return 'english'                 if $always_return_useable;
    return;
}

sub get_legacy_name_list {
    _load_oldnames();

    # we want NAME-utf8 to be listed before its non utf-8 NAME
    # we want .local before it's non-.local
    return sort { $a =~ m/\.local$/ ? $a cmp $b : $b cmp $a } keys %oldname_to_locale;
}

sub get_existing_filesys_legacy_name_list {

    require Cpanel::SafeDir::Read;

    # we want NAME-utf8 to be listed before its non utf-8 NAME
    # we want .local before it's non-.local
    my %args = @_;
    my @extras;
    if ( exists $args{'also_look_in'} && ref $args{'also_look_in'} eq 'ARRAY' ) {
        for my $path ( @{ $args{'also_look_in'} } ) {
            my $copy = $path;
            $copy =~ s/\/lang$//;
            next if !-d "$copy/lang";
            push @extras, Cpanel::SafeDir::Read::read_dir("$copy/lang");
        }
    }

    # TODO: change this back into a sort()
    my @local_less_names;
    my %has_local;
    my @names;

    my $legacy_dir = Cpanel::Locale::Utils::Paths::get_legacy_lang_root();
    for my $name ( grep { $_ !~ m/^\./ } ( $args{'no_root'} ? () : Cpanel::SafeDir::Read::read_dir($legacy_dir) ), @extras ) {
        my $copy = $name;
        if ( $copy =~ s/\.local$// ) {
            $has_local{$copy}++;
        }
        else {
            push @local_less_names, $copy;
        }
    }

    for my $name_localless ( sort { $b cmp $a } @local_less_names ) {
        push @names, exists $has_local{$name_localless} ? ( "$name_localless.local", $name_localless ) : $name_localless;
    }

    return @names;
}

sub get_legacy_root_in_locale_database_root {
    return Cpanel::Locale::Utils::Paths::get_locale_database_root() . '/legacy';
}

sub get_legacy_file_cache_path {
    my ($legacy_file) = @_;
    $legacy_file .= 'cache';
    my $legacy_dir = Cpanel::Locale::Utils::Paths::get_legacy_lang_root();
    $legacy_file =~ s{$legacy_dir}{/var/cpanel/lang.cache};
    return $legacy_file;
}

# this is a one way transition as we can't really do the opposite lookup,
# e.g. if you asked for 'en' would we return 'english' or 'english-utf8
sub map_any_old_style_to_new_style {
    return wantarray
      ? map { get_new_langtag_of_old_style_langname($_) || $_ } @_
      : get_new_langtag_of_old_style_langname( $_[0] ) || $_[0];
}

my %charset_lookup;

sub _determine_via_disassemble {
    my ( $lcl, $oldlang ) = @_;

    my ( $language, $territory, $encoding, $probable_ext );
    my @parts = split( /[^A-Za-z0-9]+/, $oldlang );    # We can't use Cpanel::CPAN::Locales::normalize_tag since it breaks things into 8 character chunks

    return if @parts == 1;                             # we've already tried just $parts[0] if the split is only 1 item
    return if @parts > 4;                              # if there are more than 4 parts then there is unresolveable data

    if ( !ref($lcl) ) {
        $lcl = Cpanel::CPAN::Locales->new($lcl) or return;
    }

    for my $part (@parts) {
        my $found_part = 0;
        if ( $lcl->get_code_from_language($part) || $lcl->get_language_from_code($part) ) {
            if ($language) {
                if ( !$lcl->get_territory_from_code($part) ) {

                    # warn "multi langauge codes";
                    return;
                }
            }
            else {
                $found_part++;
                $language = $lcl->get_language_from_code($part) ? $part : $lcl->get_code_from_language($part);
            }
        }

        if ( !$found_part && ( $lcl->get_code_from_territory($part) || $lcl->get_territory_from_code($part) ) ) {
            if ($territory) {

                # warn "multi territory codes";
                return;
            }
            else {
                $found_part++;
                $territory = $lcl->get_territory_from_code($part) ? $part : $lcl->get_code_from_territory($part);
            }
        }
        if ( !$found_part ) {
            if ( $part eq $parts[$#parts] ) {    # && length($part) < $max_len_for_ext
                $probable_ext = $part;
            }
            else {
                if ( !%charset_lookup ) {
                    require Cpanel::Locale::Utils::Charmap;

                    # normalize charset names in the same way we normalize locale tags so they will match
                    @charset_lookup{ map { Cpanel::Locale::Utils::Normalize::normalize_tag($_) } Cpanel::Locale::Utils::Charmap::get_charmap_list() } = ();
                }

                if ( $charset_lookup{$part} ) {
                    $found_part++;
                    $encoding = $part;
                }
                else {
                    return;
                }
            }
        }
    }

    if ($encoding) {

        # warn "found encoding in the name, make sure it reflect your data";
    }

    if ($probable_ext) {

        # warn "Assuming '$probable_ext' is a file extension since it was not a language, territory, or character set and it was at the end";
    }

    if ($language) {
        if ($territory) {
            return "$language\_$territory";
        }
        else {
            return $language;
        }
    }

    return;
}

#This will die() if the Locales.pm load fails.
sub real_get_new_langtag_of_old_style_langname {
    my ($oldlang) = @_;
    $oldlang = Cpanel::StringFunc::Case::ToLower($oldlang) || "";    # case 34321 item #3

    $oldlang =~ s/\.legacy_duplicate\..+$//;                         # This '.legacy_duplicate. naming hack' is for copying legacy file into a name that maps back to it's new target locale

    if ( !defined $oldlang || $oldlang eq '' || $oldlang =~ m/^\s+$/ ) {

        # no legacy lang given, warn ?
        return;                                                      # return a value ?, what is safe ...
    }
    elsif ( Cpanel::Locale::Utils::Normalize::normalize_tag($oldlang) eq 'default' ) {

        # i_default is special, warn ?
        return;                                                      # return 'en' ? could be an incorrect assumption ...
    }
    elsif ( exists $oldname_to_locale{$oldlang} ) {
        return $oldname_to_locale{$oldlang};
    }

    #Locales.pm publishes to $@.
    {
        local $@;
        $loc ||= Cpanel::CPAN::Locales->new('en') or die $@;
    }

    # '$oldlang' is already a known ISO code
    my $return;
    if ( $loc->get_language_from_code($oldlang) ) {
        $return = Cpanel::Locale::Utils::Normalize::normalize_tag($oldlang);    # case 34321 item #4
    }
    else {

        # '$oldlang' is a known ISO code's name
        my $locale = $loc->get_code_from_language($oldlang);
        if ($locale) {
            $return = $locale;    # case 34321 item #2
        }
        else {
            $return = _determine_via_disassemble( $loc, $oldlang );

            if ( !$return ) {

                # under cpsrvd the eval that Cpanel::CPAN::Locales->new() does triggers its die handler.
                # That sends the error to the log and browser and ends the request, in
                # this case prematurley, so we disable the handler (and similar ones) here
                local $SIG{'__DIE__'};    # may be made moot by case 50857
                for my $nen ( grep { $_ ne 'en' } sort( $loc->get_language_codes() ) ) {

                    # next if $nen eq 'en';

                    my $loca = Cpanel::CPAN::Locales->new($nen) or next;    # singleton

                    # '$oldlang' is a known ISO code's name in $nen
                    my $locale = $loca->get_code_from_language($oldlang);
                    if ($locale) {
                        $return = $locale;                                  # case 34321 item #2
                        last;
                    }
                    else {
                        $return = _determine_via_disassemble( $loca, $oldlang );
                        last if $return;
                    }
                }
            }
        }
    }

    if ( !$return ) {

        # if all else fails, turn it into the standard tag for non-standard names
        $return = Cpanel::CPAN::Locales::get_i_tag_for_string($oldlang);
    }

    return $return;
}

sub get_new_langtag_of_old_style_langname {
    _load_oldnames();
    require Cpanel::StringFunc::Case;
    require Cpanel::CPAN::Locales;
    $loc = Cpanel::CPAN::Locales->new('en');
    {
        no warnings 'redefine';
        *get_new_langtag_of_old_style_langname = \&real_get_new_langtag_of_old_style_langname;
    }
    goto &real_get_new_langtag_of_old_style_langname;
}

my $legacy_lookup;

sub phrase_is_legacy_key {
    my ($key) = @_;
    if ( !$legacy_lookup ) {
        require 'Cpanel/Locale/Utils/MkDB.pm';    ## no critic qw(Bareword) - hide from perlpkg
        $legacy_lookup = {
            %{ Cpanel::Locale::Utils::MkDB::get_hash_of_legacy_file( Cpanel::Locale::Utils::Paths::get_legacy_lang_root() . '/english-utf8' ) || {} },
            %{ Cpanel::Locale::Utils::MkDB::get_hash_of_legacy_file('/usr/local/cpanel/base/frontend/jupiter/lang/english-utf8') || {} },
        };
    }

    return exists $legacy_lookup->{$key} ? 1 : 0;
}

sub fetch_legacy_lookup {
    return $legacy_lookup if $legacy_lookup;
    phrase_is_legacy_key('');    # ensure $legacy_lookup is loaded
    return $legacy_lookup;
}

sub get_legacy_key_english_value {
    my ($key) = @_;
    if ( phrase_is_legacy_key($key) ) {    # inits $legacy_lookup cache
        return $legacy_lookup->{$key};
    }

    return;
}

1;
