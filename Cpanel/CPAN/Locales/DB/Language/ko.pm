package Cpanel::CPAN::Locales::DB::Language::ko;

use strict;

#use warnings;

# Auto generated from CLDR

$Cpanel::CPAN::Locales::DB::Language::ko::VERSION = '0.09';

$Cpanel::CPAN::Locales::DB::Language::ko::cldr_version = '2.0';

%Cpanel::CPAN::Locales::DB::Language::ko::misc_info = (
    'characters'   => { 'more_information' => "\?" },
    'cldr_formats' => {
        '_decimal_format_decimal' => "\.",
        '_decimal_format_group'   => "\,",
        '_percent_format_percent' => "\%",
        'decimal'                 => "\#\,\#\#0\.\#\#\#",
        'ellipsis'                => {
            'final'   => "\{0\}…",
            'initial' => "…\{0\}",
            'medial'  => "\{0\}\.\.\.\{1\}"
        },
        'language' => "언어\:\ \{0\}",
        'list'     => {
            2        => "\{0\}\ 및\ \{1\}",
            'end'    => "\{0\}\ 및\ \{1\}",
            'middle' => "\{0\}\,\ \{1\}",
            'start'  => "\{0\}\,\ \{1\}"
        },
        'locale'    => "\{0\}\(\{1\}\)",
        'percent'   => "\#\,\#\#0\%",
        'territory' => "지역\:\ \{0\}"
    },
    'delimiters' => {
        'alternate_quotation_end'   => '”',
        'alternate_quotation_start' => '“',
        'quotation_end'             => '’',
        'quotation_start'           => '‘'
    },
    'fallback'    => [],
    'orientation' => {
        'characters' => "left\-to\-right",
        'lines'      => "top\-to\-bottom"
    },
    'plural_forms' => {
        'category_list'  => ['other'],
        'category_rules' => {}
    },
    'posix' => {
        'nostr'  => '아니오',
        'yesstr' => '예'
    },
);

#name_to_code is only generated when needed for memory
$Cpanel::CPAN::Locales::DB::Language::ko::misc_info{cldr_formats}{list_or} = {
  'end' => "{0} \x{eb}\x{98}\x{90}\x{eb}\x{8a}\x{94} {1}",
  'middle' => '{0}, {1}',
  'start' => '{0}, {1}',
  '2' => "{0} \x{eb}\x{98}\x{90}\x{eb}\x{8a}\x{94} {1}"
};

1;

