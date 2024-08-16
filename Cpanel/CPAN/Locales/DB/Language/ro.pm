package Cpanel::CPAN::Locales::DB::Language::ro;

use strict;

#use warnings;

# Auto generated from CLDR

$Cpanel::CPAN::Locales::DB::Language::ro::VERSION = '0.09';

$Cpanel::CPAN::Locales::DB::Language::ro::cldr_version = '2.0';

%Cpanel::CPAN::Locales::DB::Language::ro::misc_info = (
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
        'language' => "Limbă\:\ \{0\}",
        'list'     => {
            2        => "\{0\}\ şi\ \{1\}",
            'end'    => "\{0\}\ şi\ \{1\}",
            'middle' => "\{0\}\,\ \{1\}",
            'start'  => "\{0\}\,\ \{1\}"
        },
        'locale'    => "\{0\}\ \(\{1\}\)",
        'percent'   => "\#\,\#\#0\%",
        'territory' => "Regiune\:\ \{0\}"
    },
    'delimiters' => {
        'alternate_quotation_end'   => '»',
        'alternate_quotation_start' => '«',
        'quotation_end'             => '”',
        'quotation_start'           => '„'
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
            'other'
        ],
        'category_rules' => {
            'few' => "n\ is\ 0\ OR\ n\ is\ not\ 1\ AND\ n\ mod\ 100\ in\ 1\.\.19",
            'one' => "n\ is\ 1"
        },
        'category_rules_compiled' => {
            'few' => sub {
                if ( ( ( $_[0] == 0 ) ) || ( ( $_[0] != 1 ) && ( int( $_[0] ) == $_[0] && ( ( $_[0] % 100 ) + ( $_[0] - int( $_[0] ) ) ) >= 1 && ( ( $_[0] % 100 ) + ( $_[0] - int( $_[0] ) ) ) <= 19 ) ) ) { return 'few'; }
                return;
            },
            'one' => sub {
                if ( ( ( $_[0] == 1 ) ) ) { return 'one'; }
                return;
            }
        }
    },
    'posix' => {
        'nostr'  => "nu\:n",
        'yesstr' => "da\:d"
    },
);



#name_to_code is only generated when needed for memory
$Cpanel::CPAN::Locales::DB::Language::ro::misc_info{cldr_formats}{list_or} = {
  'start' => '{0}, {1}',
  '2' => '{0} sau {1}',
  'middle' => '{0}, {1}',
  'end' => '{0} sau {1}'
};

1;

