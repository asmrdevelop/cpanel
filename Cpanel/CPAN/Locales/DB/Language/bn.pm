package Cpanel::CPAN::Locales::DB::Language::bn;

use strict;

#use warnings;

# Auto generated from CLDR

$Cpanel::CPAN::Locales::DB::Language::bn::VERSION = '0.09';

$Cpanel::CPAN::Locales::DB::Language::bn::cldr_version = '2.0';

%Cpanel::CPAN::Locales::DB::Language::bn::misc_info = (
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
        'language' => "ভাষা\:\ \{0\}",
        'list'     => {
            2        => "\{0\}\ এবং\ \{1\}",
            'end'    => "\{0\}\,\ এবং\ \{1\}",
            'middle' => "\{0\}\,\ \{1\}",
            'start'  => "\{0\}\,\ \{1\}"
        },
        'locale'    => "\{0\}\ \(\{1\}\)",
        'percent'   => "\#\,\#\#\,\#\#0\%",
        'territory' => "অঞ্চল\:\ \{0\}"
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
        'nostr'  => 'না',
        'yesstr' => 'হাঁ'
    },
);



#name_to_code is only generated when needed for memory
$Cpanel::CPAN::Locales::DB::Language::bn::misc_info{cldr_formats}{list_or} = {
  'middle' => '{0}, {1}',
  'end' => "{0}, \x{e0}\x{a6}\x{ac}\x{e0}\x{a6}\x{be} {1}",
  'start' => '{0}, {1}',
  '2' => "{0} \x{e0}\x{a6}\x{ac}\x{e0}\x{a6}\x{be} {1}"
};

1;

