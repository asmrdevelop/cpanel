package Cpanel::CPAN::Locales::DB::Language::kk;

use strict;

#use warnings;

# Auto generated from CLDR

$Cpanel::CPAN::Locales::DB::Language::kk::VERSION = '0.09';

$Cpanel::CPAN::Locales::DB::Language::kk::cldr_version = '2.0';

%Cpanel::CPAN::Locales::DB::Language::kk::misc_info = (
    'characters'   => { 'more_information' => "\?" },
    'cldr_formats' => {
        '_decimal_format_decimal' => "\,",
        '_decimal_format_group'   => ' ',
        '_percent_format_percent' => "\%",
        'decimal'                 => "\#\,\#\#0\.\#\#\#",
        'ellipsis'                => {
            'final'   => "\{0\}…",
            'initial' => "…\{0\}",
            'medial'  => "\{0\}…\{1\}"
        },
        'language' => "Тіл\:\ \{0\}",
        'list'     => {
            2        => "\{0\}\ and\ \{1\}",
            'end'    => "\{0\}\,\ and\ \{1\}",
            'middle' => "\{0\}\,\ \{1\}",
            'start'  => "\{0\}\,\ \{1\}"
        },
        'locale'    => "\{0\}\ \(\{1\}\)",
        'percent'   => "\#\,\#\#0\%",
        'territory' => "Аймақ\:\ \{0\}"
    },
    'delimiters' => {
        'alternate_quotation_end'   => "\â\\",
        'alternate_quotation_start' => "\â\\",
        'quotation_end'             => "\â\\",
        'quotation_start'           => "\â\\"
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
        'nostr'  => "жоқ\:ж",
        'yesstr' => "иә\:и"
    },
);



#name_to_code is only generated when needed for memory
$Cpanel::CPAN::Locales::DB::Language::kk::misc_info{cldr_formats}{list_or} = {
  'middle' => '{0}, {1}',
  'end' => "{0}, \x{d0}\x{bd}\x{d0}\x{b5} \x{d0}\x{b1}\x{d0}\x{be}\x{d0}\x{bb}\x{d0}\x{bc}\x{d0}\x{b0}\x{d1}\x{81}\x{d0}\x{b0} {1}",
  '2' => "{0} \x{d0}\x{bd}\x{d0}\x{b5} {1}",
  'start' => '{0}, {1}'
};

1;
