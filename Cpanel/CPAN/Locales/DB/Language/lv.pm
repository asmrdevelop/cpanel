package Cpanel::CPAN::Locales::DB::Language::lv;

use strict;

#use warnings;

# Auto generated from CLDR

$Cpanel::CPAN::Locales::DB::Language::lv::VERSION = '0.09';

$Cpanel::CPAN::Locales::DB::Language::lv::cldr_version = '2.0';

%Cpanel::CPAN::Locales::DB::Language::lv::misc_info = (
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
        'language' => "Valoda\:\ \{0\}",
        'list'     => {
            2        => "\{0\}\ un\ \{1\}",
            'end'    => "\{0\}\ un\ \{1\}",
            'middle' => "\{0\}\,\ \{1\}",
            'start'  => "\{0\}\,\ \{1\}"
        },
        'locale'    => "\{0\}\ \(\{1\}\)",
        'percent'   => "\#\,\#\#0\%",
        'territory' => "Reģions\:\ \{0\}"
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
            'zero',
            'other'
        ],
        'category_rules' => {
            'one'  => "n\ mod\ 10\ is\ 1\ and\ n\ mod\ 100\ is\ not\ 11",
            'zero' => "n\ is\ 0"
        },
        'category_rules_compiled' => {
            'one' => sub {
                if ( ( ( ( ( $_[0] % 10 ) + ( $_[0] - int( $_[0] ) ) ) == 1 ) && ( ( ( $_[0] % 100 ) + ( $_[0] - int( $_[0] ) ) ) != 11 ) ) ) { return 'one'; }
                return;
            },
            'zero' => sub {
                if ( ( ( $_[0] == 0 ) ) ) { return 'zero'; }
                return;
            }
        }
    },
    'posix' => {
        'nostr'  => "nē\:ne\:n",
        'yesstr' => "jā\:ja\:j"
    },
);



#name_to_code is only generated when needed for memory
$Cpanel::CPAN::Locales::DB::Language::lv::misc_info{cldr_formats}{list_or} = {
  'end' => '{0} vai {1}',
  'middle' => '{0}, {1}',
  '2' => '{0} vai {1}',
  'start' => '{0}, {1}'
};

1;

