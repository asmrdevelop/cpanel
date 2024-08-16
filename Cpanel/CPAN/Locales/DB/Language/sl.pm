package Cpanel::CPAN::Locales::DB::Language::sl;

use strict;

#use warnings;

# Auto generated from CLDR

$Cpanel::CPAN::Locales::DB::Language::sl::VERSION = '0.09';

$Cpanel::CPAN::Locales::DB::Language::sl::cldr_version = '2.0';

%Cpanel::CPAN::Locales::DB::Language::sl::misc_info = (
    'characters'   => { 'more_information' => "\?" },
    'cldr_formats' => {
        '_decimal_format_decimal' => "\,",
        '_decimal_format_group'   => "\.",
        '_percent_format_percent' => "\%",
        'decimal'                 => "\#\,\#\#0\.\#\#\#",
        'ellipsis'                => {
            'final'   => "\{0\}…",
            'initial' => "…\{0\}",
            'medial'  => "\{0\}…\{1\}"
        },
        'language' => "Jezik\:\ \{0\}",
        'list'     => {
            2        => "\{0\}\ in\ \{1\}",
            'end'    => "\{0\}\ in\ \{1\}",
            'middle' => "\{0\}\,\ \{1\}",
            'start'  => "\{0\}\,\ \{1\}"
        },
        'locale'    => "\{0\}\ \(\{1\}\)",
        'percent'   => "\#\,\#\#0\%",
        'territory' => "Regija\:\ \{0\}"
    },
    'delimiters' => {
        'alternate_quotation_end'   => '“',
        'alternate_quotation_start' => '„',
        'quotation_end'             => '«',
        'quotation_start'           => '»'
    },
    'fallback'    => [],
    'orientation' => {
        'characters' => "left\-to\-right",
        'lines'      => "top\-to\-bottom"
    },
    'plural_forms' => {
        'category_list' => [
            'one',
            'two',
            'few',
            'other'
        ],
        'category_rules' => {
            'few' => "n\ mod\ 100\ in\ 3\.\.4",
            'one' => "n\ mod\ 100\ is\ 1",
            'two' => "n\ mod\ 100\ is\ 2"
        },
        'category_rules_compiled' => {
            'few' => sub {
                if ( ( ( int( $_[0] ) == $_[0] && ( ( $_[0] % 100 ) + ( $_[0] - int( $_[0] ) ) ) >= 3 && ( ( $_[0] % 100 ) + ( $_[0] - int( $_[0] ) ) ) <= 4 ) ) ) { return 'few'; }
                return;
            },
            'one' => sub {
                if ( ( ( ( ( $_[0] % 100 ) + ( $_[0] - int( $_[0] ) ) ) == 1 ) ) ) { return 'one'; }
                return;
            },
            'two' => sub {
                if ( ( ( ( ( $_[0] % 100 ) + ( $_[0] - int( $_[0] ) ) ) == 2 ) ) ) { return 'two'; }
                return;
            }
        }
    },
    'posix' => {
        'nostr'  => "ne\:n",
        'yesstr' => "da\:d"
    },
);



#name_to_code is only generated when needed for memory
$Cpanel::CPAN::Locales::DB::Language::sl::misc_info{cldr_formats}{list_or} = {
  'middle' => '{0}, {1}',
  'end' => '{0} ali {1}',
  '2' => '{0} ali {1}',
  'start' => '{0}, {1}'
};

1;

