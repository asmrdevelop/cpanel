package Cpanel::Locale::Utils::3rdparty;

# cpanel - Cpanel/Locale/Utils/3rdparty.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our %cpanel_provided = (
    'de'               => 1,
    'en'               => 1,
    'es_es'            => 1,
    'i_cpanel_snowmen' => 1,
    'ru'               => 1,
    'pt_br'            => 1,
    'ja'               => 1,
    'tr'               => 1,
    'id',              => 1,
);

my %locale_to_3rdparty;

sub _load_3rdparty {
    return if (%locale_to_3rdparty);

    %locale_to_3rdparty = (
        'ar' => {
            'analog'    => 'us',
            'awstats'   => 'ar',
            'webalizer' => 'english'
        },
        'bg' => {
            'analog'    => 'bg',
            'awstats'   => 'bg',
            'webalizer' => 'english'
        },
        'bn' => {
            'analog'    => 'us',
            'awstats'   => 'en',
            'webalizer' => 'english'
        },
        'de' => {
            'analog'    => 'de',
            'awstats'   => 'de',
            'webalizer' => 'german'
        },
        'en' => {
            'analog'    => 'us',
            'awstats'   => 'en',
            'webalizer' => 'english'
        },
        'es' => {
            'analog'    => 'es',
            'awstats'   => 'es',
            'webalizer' => 'spanish'
        },
        'es_es' => {
            'analog'    => 'es',
            'awstats'   => 'es',
            'webalizer' => 'spanish'
        },
        'fi' => {
            'analog'    => 'fi',
            'awstats'   => 'fi',
            'webalizer' => 'finnish'
        },
        'fr' => {
            'analog'    => 'fr',
            'awstats'   => 'fr',
            'webalizer' => 'french'
        },
        'hi' => {
            'analog'    => 'us',
            'awstats'   => 'en',
            'webalizer' => 'english'
        },
        'hu' => {
            'analog'    => 'hu',
            'awstats'   => 'hu',
            'webalizer' => 'hungarian'
        },
        'id' => {
            'analog'    => 'us',
            'awstats'   => 'id',
            'webalizer' => 'indonesian'
        },
        'it' => {
            'analog'    => 'it',
            'awstats'   => 'it',
            'webalizer' => 'italian'
        },
        'ja' => {
            'analog'    => 'jpu',       # appears to be the UTF-8 one
            'awstats'   => 'jp',
            'webalizer' => 'japanese'
        },
        'ko' => {
            'analog'    => 'us',
            'awstats'   => 'ko',
            'webalizer' => 'korean'
        },
        'nl' => {
            'analog'    => 'nl',
            'awstats'   => 'nl',
            'webalizer' => 'dutch'
        },
        'no' => {
            'analog'    => 'no',
            'awstats'   => 'en',
            'webalizer' => 'norwegian'
        },
        'pl' => {
            'analog'    => 'pl',
            'awstats'   => 'pl',
            'webalizer' => 'polish'
        },
        'pt' => {
            'analog'    => 'pt',
            'awstats'   => 'pt',
            'webalizer' => 'portuguese'
        },
        'pt_br' => {
            'analog'    => 'pt',
            'awstats'   => 'pt',
            'webalizer' => 'portuguese_brazil'
        },
        'ro' => {
            'analog'    => 'ro',
            'awstats'   => 'ro',
            'webalizer' => 'romanian'
        },
        'ru' => {
            'analog'    => 'ru',
            'awstats'   => 'ru',
            'webalizer' => 'russian'
        },
        'sl' => {
            'analog'    => 'us',
            'awstats'   => 'en',
            'webalizer' => 'slovene'
        },
        'sv' => {
            'analog'    => 'us',
            'awstats'   => 'en',
            'webalizer' => 'swedish'
        },
        'th' => {
            'analog'    => 'us',
            'awstats'   => 'th',
            'webalizer' => 'english'
        },
        'tr' => {
            'analog'    => 'tr',
            'awstats'   => 'tr',
            'webalizer' => 'turkish'
        },
        'zh' => {
            'analog'    => 'cn',       # the cn.lng does not say what it is so this is an assumption based on other pervasive bad practices
            'awstats'   => 'cn',
            'webalizer' => 'chinese'
        },
        'zh_cn' => {
            'analog'    => 'cn',                  # the cn.lng does not say what it is so this is an assumption based on other pervasive bad practices
            'awstats'   => 'cn',
            'webalizer' => 'simplified_chinese'
        },
    );
}

sub get_known_3rdparty_lang {
    my ( $locale, $_3rdparty ) = @_;
    _load_3rdparty();
    my $locale_tag = ref $locale ? $locale->get_language_tag() : $locale;
    $locale_tag = 'en' if $locale_tag eq 'en_us' || $locale_tag eq 'i_default';

    return if !exists $locale_to_3rdparty{$locale_tag};
    return if !exists $locale_to_3rdparty{$locale_tag}{$_3rdparty};
    return $locale_to_3rdparty{$locale_tag}{$_3rdparty};
}

my %locale_lookup_cache;

sub get_3rdparty_lang {
    my ( $locale, $_3rdparty ) = @_;
    my $known = get_known_3rdparty_lang( $locale, $_3rdparty );
    return $known if $known;

    return if !ref($locale) && $locale =~ m/(?:\.\.|\/)/;
    return if $_3rdparty               =~ m/(?:\.\.|\/)/;

    my $locale_tag = ref $locale ? $locale->get_language_tag() : $locale;
    $locale_tag = 'en' if $locale_tag eq 'en_us' || $locale_tag eq 'i_default';

    if ( exists $locale_lookup_cache{$_3rdparty} ) {
        return $locale_lookup_cache{$_3rdparty}{$locale_tag} if exists $locale_lookup_cache{$_3rdparty}{$locale_tag};
        return;
    }
    require Cpanel::DataStore;
    my $hr = Cpanel::DataStore::fetch_ref("/var/cpanel/locale/3rdparty/apps/$_3rdparty.yaml");
    my %seen;
    %{ $locale_lookup_cache{$_3rdparty} } = map { ++$seen{ $hr->{$_} } == 1 ? ( $hr->{$_} => $_ ) : () } keys %{$hr};

    return $locale_lookup_cache{$_3rdparty}{$locale_tag} if exists $locale_lookup_cache{$_3rdparty}{$locale_tag};
    return;
}

my @list;

sub get_3rdparty_list {
    return @list if @list;

    @list = qw(analog awstats webalizer);

    if ( -d "/var/cpanel/locale/3rdparty/apps" ) {
        require Cpanel::SafeDir::Read;
        push @list, sort map { my $f = $_; $f =~ s/\.yaml$// ? ($f) : () } Cpanel::SafeDir::Read::read_dir("/var/cpanel/locale/3rdparty/apps");
    }

    return @list;
}

my %opt_cache;

sub get_app_options {
    my ($_3rdparty) = @_;
    return if $_3rdparty =~ m/(?:\.\.|\/)/;

    return $opt_cache{$_3rdparty} if exists $opt_cache{$_3rdparty};
    if ( $_3rdparty eq 'analog' || $_3rdparty eq 'awstats' || $_3rdparty eq 'webalizer' ) {
        _load_3rdparty();
        my %seen;
        $opt_cache{$_3rdparty} = [ sort map { ++$seen{ $locale_to_3rdparty{$_}{$_3rdparty} } == 1 ? ( $locale_to_3rdparty{$_}{$_3rdparty} ) : () } keys %locale_to_3rdparty ];
    }
    else {
        require Cpanel::DataStore;
        my $hr = Cpanel::DataStore::fetch_ref("/var/cpanel/locale/3rdparty/apps/$_3rdparty.yaml");
        $opt_cache{$_3rdparty} = [ sort keys %{$hr} ];
    }

    return $opt_cache{$_3rdparty};
}

sub get_app_setting {
    my ( $locale, $_3rdparty ) = @_;

    return if !ref($locale) && $locale =~ m/(?:\.\.|\/)/;
    return if $_3rdparty               =~ m/(?:\.\.|\/)/;

    require Cpanel::LoadFile;
    require Cpanel::StringFunc::Trim;

    my $locale_tag = ref $locale ? $locale->get_language_tag() : $locale;
    $locale_tag = 'en' if $locale_tag eq 'en_us' || $locale_tag eq 'i_default';

    my $setting = Cpanel::StringFunc::Trim::ws_trim( Cpanel::LoadFile::loadfile("/var/cpanel/locale/3rdparty/conf/$locale_tag/$_3rdparty") ) || '';
    if ( $_3rdparty eq 'analog' && $setting eq 'en' ) {
        $setting = 'us';
    }

    return $setting;
}

sub set_app_setting {
    my ( $locale, $_3rdparty, $setting ) = @_;

    return if !ref($locale) && $locale =~ m/(?:\.\.|\/)/;
    return if $_3rdparty               =~ m/(?:\.\.|\/)/;

    require Cpanel::SafeDir::MK;
    require Cpanel::FileUtils::Write;

    my $locale_tag = ref $locale ? $locale->get_language_tag() : $locale;
    $locale_tag = 'en' if $locale_tag eq 'en_us' || $locale_tag eq 'i_default';

    Cpanel::SafeDir::MK::safemkdir("/var/cpanel/locale/3rdparty/conf/$locale_tag/");
    Cpanel::FileUtils::Write::overwrite_no_exceptions( "/var/cpanel/locale/3rdparty/conf/$locale_tag/$_3rdparty", $setting, 0644 );

    return;
}

1;
