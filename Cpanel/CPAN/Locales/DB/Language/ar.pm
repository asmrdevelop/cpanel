package Cpanel::CPAN::Locales::DB::Language::ar;

use strict;

#use warnings;

# Auto generated from CLDR

$Cpanel::CPAN::Locales::DB::Language::ar::VERSION = '0.09';

$Cpanel::CPAN::Locales::DB::Language::ar::cldr_version = '2.0';

%Cpanel::CPAN::Locales::DB::Language::ar::misc_info = (
    'characters'   => { 'more_information' => "\?" },
    'cldr_formats' => {
        '_decimal_format_decimal' => '٫',
        '_decimal_format_group'   => '٬',
        '_percent_format_percent' => '٪',
        'decimal'                 => "\#\,\#\#0\.\#\#\#\;\#\,\#\#0\.\#\#\#\-",
        'ellipsis'                => {
            'final'   => "\{0\}…",
            'initial' => "…\{0\}",
            'medial'  => "\{0\}…\{1\}"
        },
        'language' => "اللغة\:\ \{0\}",
        'list'     => {
            2        => "\{0\}\ و\ \{1\}",
            'end'    => "\{0\}،\ و\ \{1\}",
            'middle' => "\{0\}،\ \{1\}",
            'start'  => "\{0\}،\ \{1\}"
        },
        'locale'    => "\{0\}\ \(\{1\}\)",
        'percent'   => "\#\,\#\#0\%",
        'territory' => "المنطقة\:\ \{0\}"
    },
    'delimiters' => {
        'alternate_quotation_end'   => '’',
        'alternate_quotation_start' => '‘',
        'quotation_end'             => '”',
        'quotation_start'           => '“'
    },
    'fallback'    => [],
    'orientation' => {
        'characters' => "right\-to\-left",
        'lines'      => "top\-to\-bottom"
    },
    'plural_forms' => {
        'category_list' => [
            'one',
            'two',
            'few',
            'many',
            'zero',
            'other'
        ],
        'category_rules' => {
            'few'  => "n\ mod\ 100\ in\ 3\.\.10",
            'many' => "n\ mod\ 100\ in\ 11\.\.99",
            'one'  => "n\ is\ 1",
            'two'  => "n\ is\ 2",
            'zero' => "n\ is\ 0"
        },
        'category_rules_compiled' => {
            'few' => sub {
                if ( ( ( int( $_[0] ) == $_[0] && ( ( $_[0] % 100 ) + ( $_[0] - int( $_[0] ) ) ) >= 3 && ( ( $_[0] % 100 ) + ( $_[0] - int( $_[0] ) ) ) <= 10 ) ) ) { return 'few'; }
                return;
            },
            'many' => sub {
                if ( ( ( int( $_[0] ) == $_[0] && ( ( $_[0] % 100 ) + ( $_[0] - int( $_[0] ) ) ) >= 11 && ( ( $_[0] % 100 ) + ( $_[0] - int( $_[0] ) ) ) <= 99 ) ) ) { return 'many'; }
                return;
            },
            'one' => sub {
                if ( ( ( $_[0] == 1 ) ) ) { return 'one'; }
                return;
            },
            'two' => sub {
                if ( ( ( $_[0] == 2 ) ) ) { return 'two'; }
                return;
            },
            'zero' => sub {
                if ( ( ( $_[0] == 0 ) ) ) { return 'zero'; }
                return;
            }
        }
    },
    'posix' => {
        'nostr'  => "لا\:ل",
        'yesstr' => "نعم\:ن"
    },
);



#name_to_code is only generated when needed for memory
$Cpanel::CPAN::Locales::DB::Language::ar::misc_info{cldr_formats}{list_or} = {
  'middle' => "{0} \x{d9}\x{88}{1}",
  'end' => "{0} \x{d8}\x{a3}\x{d9}\x{88} {1}",
  '2' => "{0} \x{d8}\x{a3}\x{d9}\x{88} {1}",
  'start' => "{0} \x{d9}\x{88}{1}"
};

1;

