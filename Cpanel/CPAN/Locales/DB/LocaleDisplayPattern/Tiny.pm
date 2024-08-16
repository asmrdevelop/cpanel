package Cpanel::CPAN::Locales::DB::LocaleDisplayPattern::Tiny;

use strict;

#use warnings;

# Auto generated from CLDR

$Cpanel::CPAN::Locales::DB::LocaleDisplayPattern::Tiny::VERSION = '0.09';

$Cpanel::CPAN::Locales::DB::LocaleDisplayPattern::Tiny::cldr_version = '2.0';

my %locale_display_lookup = (
    'ksh' => '{0} en {1}',
    'ja'  => '{0}({1})',
    'zh'  => '{0}（{1}）',
    'ko'  => '{0}({1})',
);

sub get_locale_display_pattern {
    if ( exists $locale_display_lookup{ $_[0] } ) {
        return $locale_display_lookup{ $_[0] };
    }
    else {
        require Cpanel::CPAN::Locales;
        my ($l) = Cpanel::CPAN::Locales::split_tag( $_[0] );
        if ( $l ne $_[0] ) {
            return $locale_display_lookup{$l} if exists $locale_display_lookup{$l};
        }
        return "\{0\}\ \(\{1\}\)";
    }
}

1;
