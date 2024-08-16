package Cpanel::CPAN::Locales::DB::Language::mt;

use strict;

#use warnings;

# Auto generated from CLDR

$Cpanel::CPAN::Locales::DB::Language::mt::VERSION = '0.09';

$Cpanel::CPAN::Locales::DB::Language::mt::cldr_version = '2.0';

%Cpanel::CPAN::Locales::DB::Language::mt::misc_info = (
    'characters'   => { 'more_information' => "\?" },
    'cldr_formats' => {
        '_decimal_format_decimal' => "\.",
        '_decimal_format_group'   => "\,",
        '_percent_format_percent' => "\%",
        'decimal'                 => "\#\,\#\#0\.\#\#\#",
        'ellipsis'                => {
            'final'   => "\{0\}…",
            'initial' => "…\{0\}",
            'medial'  => "\{0\}…\{1\}"
        },
        'language' => "Lingwa\:\ \{0\}",
        'list'     => {
            2        => "\{0\}\ and\ \{1\}",
            'end'    => "\{0\}\,\ and\ \{1\}",
            'middle' => "\{0\}\,\ \{1\}",
            'start'  => "\{0\}\,\ \{1\}"
        },
        'locale'    => "\{0\}\ \(\{1\}\)",
        'percent'   => "\#\,\#\#0\%",
        'territory' => "Reġjun\:\ \{0\}"
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
            'few',
            'many',
            'other'
        ],
        'category_rules' => {
            'few'  => "n\ is\ 0\ or\ n\ mod\ 100\ in\ 2\.\.10",
            'many' => "n\ mod\ 100\ in\ 11\.\.19",
            'one'  => "n\ is\ 1"
        },
        'category_rules_compiled' => {
            'few' => sub {
                if ( ( ( $_[0] == 0 ) ) || ( ( int( $_[0] ) == $_[0] && ( ( $_[0] % 100 ) + ( $_[0] - int( $_[0] ) ) ) >= 2 && ( ( $_[0] % 100 ) + ( $_[0] - int( $_[0] ) ) ) <= 10 ) ) ) { return 'few'; }
                return;
            },
            'many' => sub {
                if ( ( ( int( $_[0] ) == $_[0] && ( ( $_[0] % 100 ) + ( $_[0] - int( $_[0] ) ) ) >= 11 && ( ( $_[0] % 100 ) + ( $_[0] - int( $_[0] ) ) ) <= 19 ) ) ) { return 'many'; }
                return;
            },
            'one' => sub {
                if ( ( ( $_[0] == 1 ) ) ) { return 'one'; }
                return;
            }
        }
    },
    'posix' => {
        'nostr'  => "le\:l",
        'yesstr' => "iva\:i"
    },
);

#name_to_code is only generated when needed for memory
$Cpanel::CPAN::Locales::DB::Language::mt::misc_info{cldr_formats}{list_or} = {
  'start' => '{0}, {1}',
  '2' => '{0} or {1}',
  'middle' => '{0}, {1}',
  'end' => '{0}, or {1}'
};

1;

