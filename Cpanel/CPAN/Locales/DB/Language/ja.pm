package Cpanel::CPAN::Locales::DB::Language::ja;

use strict;

#use warnings;

# Auto generated from CLDR

$Cpanel::CPAN::Locales::DB::Language::ja::VERSION = '0.09';

$Cpanel::CPAN::Locales::DB::Language::ja::cldr_version = '2.0';

%Cpanel::CPAN::Locales::DB::Language::ja::misc_info = (
    'characters'   => { 'more_information' => "\?" },
    'cldr_formats' => {
        '_decimal_format_decimal' => "\.",
        '_decimal_format_group'   => "\,",
        '_percent_format_percent' => "\%",
        'decimal'                 => "\#\,\#\#0\.\#\#\#",
        'ellipsis'                => {
            'final'   => "\{0\}\.\.\.",
            'initial' => "\.\.\.\{0\}",
            'medial'  => "\{0\}\.\.\.\{1\}"
        },
        'language' => "言語\:\ \{0\}",
        'list'     => {
            2        => "\{0\}、\{1\}",
            'end'    => "\{0\}、\{1\}",
            'middle' => "\{0\}、\{1\}",
            'start'  => "\{0\}、\{1\}"
        },
        'locale'    => "\{0\}\(\{1\}\)",
        'percent'   => "\#\,\#\#0\%",
        'territory' => "地域\:\ \{0\}"
    },
    'delimiters' => {
        'alternate_quotation_end'   => '』',
        'alternate_quotation_start' => '『',
        'quotation_end'             => '」',
        'quotation_start'           => '「'
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
        'nostr'  => "いいえ\:イイエ",
        'yesstr' => "はい\:ハイ"
    },
);



#name_to_code is only generated when needed for memory
$Cpanel::CPAN::Locales::DB::Language::ja::misc_info{cldr_formats}{list_or} = {
  'middle' => "{0}\x{e3}\x{80}\x{81}{1}",
  'end' => "{0}\x{e3}\x{80}\x{81}\x{e3}\x{81}\x{be}\x{e3}\x{81}\x{9f}\x{e3}\x{81}\x{af}{1}",
  '2' => "{0}\x{e3}\x{81}\x{be}\x{e3}\x{81}\x{9f}\x{e3}\x{81}\x{af}{1}",
  'start' => "{0}\x{e3}\x{80}\x{81}{1}"
};

1;

