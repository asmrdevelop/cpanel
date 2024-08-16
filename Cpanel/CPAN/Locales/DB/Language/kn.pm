package Cpanel::CPAN::Locales::DB::Language::kn;

use strict;

#use warnings;

# Auto generated from CLDR

$Cpanel::CPAN::Locales::DB::Language::kn::VERSION = '0.09';

$Cpanel::CPAN::Locales::DB::Language::kn::cldr_version = '2.0';

%Cpanel::CPAN::Locales::DB::Language::kn::misc_info = (
    'characters'   => { 'more_information' => "\?" },
    'cldr_formats' => {
        '_decimal_format_decimal' => "\.",
        '_decimal_format_group'   => "\,",
        '_percent_format_percent' => "\%",
        'decimal'                 => "\#\,\#\#\,\#\#0\.\#\#\#",
        'ellipsis'                => {
            'final'   => "\{0\}…",
            'initial' => "…\{0\}",
            'medial'  => "\{0\}…\{1\}"
        },
        'language' => "Language\:\ \{0\}",
        'list'     => {
            2        => "\{0\}\ ಮತ್ತು\ \{1\}",
            'end'    => "\{0\}\,\ ಮತ್ತು\ \{1\}",
            'middle' => "\{0\}\,\ \{1\}",
            'start'  => "\{0\}\,\ \{1\}"
        },
        'locale'    => "\{0\}\ \(\{1\}\)",
        'percent'   => "\#\,\#\#\,\#\#0\%",
        'territory' => "Region\:\ \{0\}"
    },
    'delimiters' => {
        'alternate_quotation_end'   => '’',
        'alternate_quotation_start' => '‘',
        'quotation_end'             => '”',
        'quotation_start'           => '“'
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
        'nostr'  => "ಇಲ್ಲ\:ಇ",
        'yesstr' => "ಹೌದು\:ಹೌ"
    },
);



#name_to_code is only generated when needed for memory
$Cpanel::CPAN::Locales::DB::Language::kn::misc_info{cldr_formats}{list_or} = {
  '2' => "{0} \x{e0}\x{b2}\x{85}\x{e0}\x{b2}\x{a5}\x{e0}\x{b2}\x{b5}\x{e0}\x{b2}\x{be} {1}",
  'start' => '{0}, {1}',
  'end' => "{0}, \x{e0}\x{b2}\x{85}\x{e0}\x{b2}\x{a5}\x{e0}\x{b2}\x{b5}\x{e0}\x{b2}\x{be} {1}",
  'middle' => '{0}, {1}'
};

1;

