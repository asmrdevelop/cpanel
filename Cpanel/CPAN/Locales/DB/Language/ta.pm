package Cpanel::CPAN::Locales::DB::Language::ta;

use strict;

#use warnings;

# Auto generated from CLDR

$Cpanel::CPAN::Locales::DB::Language::ta::VERSION = '0.09';

$Cpanel::CPAN::Locales::DB::Language::ta::cldr_version = '2.0';

%Cpanel::CPAN::Locales::DB::Language::ta::misc_info = (
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
        'language' => "மொழி\:\ \{0\}",
        'list'     => {
            2        => "\{0\}\ மற்றும்\ \{1\}",
            'end'    => "\{0\}\ மற்றும்\ \{1\}",
            'middle' => "\{0\}\,\ \{1\}",
            'start'  => "\{0\}\,\ \{1\}"
        },
        'locale'    => "\{0\}\ \(\{1\}\)",
        'percent'   => "\#\,\#\#\,\#\#0\%",
        'territory' => "மண்டலம்\:\ \{0\}"
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
        'category_list' => [
            'one',
            'other'
        ],
        'category_rules'          => { 'one' => "n\ is\ 1" },
        'category_rules_compiled' => {
            'one' => sub {
                if ( ( ( $_[0] == 1 ) ) ) { return 'one'; }
                return;
            }
        }
    },
    'posix' => {
        'nostr'  => "இல்லை\:இ",
        'yesstr' => "ஆம்\:ஆ"
    },
);



#name_to_code is only generated when needed for memory
$Cpanel::CPAN::Locales::DB::Language::ta::misc_info{cldr_formats}{list_or} = {
  'end' => "{0} \x{e0}\x{ae}\x{85}\x{e0}\x{ae}\x{b2}\x{e0}\x{af}\x{8d}\x{e0}\x{ae}\x{b2}\x{e0}\x{ae}\x{a4}\x{e0}\x{af}\x{81} {1}",
  'middle' => '{0}, {1}',
  '2' => "{0} \x{e0}\x{ae}\x{85}\x{e0}\x{ae}\x{b2}\x{e0}\x{af}\x{8d}\x{e0}\x{ae}\x{b2}\x{e0}\x{ae}\x{a4}\x{e0}\x{af}\x{81} {1}",
  'start' => '{0}, {1}'
};

1;

