package Cpanel::CPAN::Locales::DB::Language::fa;

use strict;

#use warnings;

# Auto generated from CLDR

$Cpanel::CPAN::Locales::DB::Language::fa::VERSION = '0.09';

$Cpanel::CPAN::Locales::DB::Language::fa::cldr_version = '2.0';

%Cpanel::CPAN::Locales::DB::Language::fa::misc_info = (
    'characters'   => { 'more_information' => '؟' },
    'cldr_formats' => {
        '_decimal_format_decimal' => '٫',
        '_decimal_format_group'   => '٬',
        '_percent_format_percent' => '٪',
        'decimal'                 => "\#\,\#\#0\.\#\#\#",
        'ellipsis'                => {
            'final'   => "\{0\}…",
            'initial' => "…\{0\}",
            'medial'  => "\{0\}…\{1\}"
        },
        'language' => "زبان\:\ \{0\}",
        'list'     => {
            2        => "\{0\}\ و\ \{1\}",
            'end'    => "\{0\}،\ و\ \{1\}",
            'middle' => "\{0\}،‏\ \{1\}",
            'start'  => "\{0\}،‏\ \{1\}"
        },
        'locale'    => "\{0\}\ \(\{1\}\)",
        'percent'   => "\#\,\#\#0\%",
        'territory' => "ناحیه\:\ \{0\}"
    },
    'delimiters' => {
        'alternate_quotation_end'   => '›',
        'alternate_quotation_start' => '‹',
        'quotation_end'             => '»',
        'quotation_start'           => '«'
    },
    'fallback'    => [],
    'orientation' => {
        'characters' => "right\-to\-left",
        'lines'      => "top\-to\-bottom"
    },
    'plural_forms' => {
        'category_list'  => ['other'],
        'category_rules' => {}
    },
    'posix' => {
        'nostr'  => "نه\:ن\:خیر\:خ",
        'yesstr' => "بله\:ب\:آری\:آ"
    },
);



#name_to_code is only generated when needed for memory
$Cpanel::CPAN::Locales::DB::Language::fa::misc_info{cldr_formats}{list_or} = {
  'start' => "{0}\x{d8}\x{8c} {1}",
  '2' => "{0} \x{db}\x{8c}\x{d8}\x{a7} {1}",
  'middle' => "{0}\x{d8}\x{8c} {1}",
  'end' => "{0}\x{d8}\x{8c} \x{db}\x{8c}\x{d8}\x{a7} {1}"
};

1;

