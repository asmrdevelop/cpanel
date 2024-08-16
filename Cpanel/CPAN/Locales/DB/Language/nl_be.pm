package Cpanel::CPAN::Locales::DB::Language::nl_be;

use strict;

#use warnings;

# Auto generated from CLDR

$Cpanel::CPAN::Locales::DB::Language::nl_be::VERSION = '0.09';

$Cpanel::CPAN::Locales::DB::Language::nl_be::cldr_version = '2.0';

%Cpanel::CPAN::Locales::DB::Language::nl_be::misc_info = (
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
        'language' => "Taal\:\ \{0\}",
        'list'     => {
            2        => "\{0\}\ en\ \{1\}",
            'end'    => "\{0\}\ en\ \{1\}",
            'middle' => "\{0\}\,\ \{1\}",
            'start'  => "\{0\}\,\ \{1\}"
        },
        'locale'    => "\{0\}\ \(\{1\}\)",
        'percent'   => "\#\,\#\#0\%",
        'territory' => "Regio\:\ \{0\}"
    },
    'delimiters' => {
        'alternate_quotation_end'   => '”',
        'alternate_quotation_start' => '“',
        'quotation_end'             => '’',
        'quotation_start'           => '‘'
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
        'nostr'  => "nee\:n",
        'yesstr' => "ja\:j"
    },
);

#name_to_code is only generated when needed for memory
$Cpanel::CPAN::Locales::DB::Language::nl_be::misc_info{cldr_formats}{list_or} = {
  'start' => '{0}, {1}',
  '2' => '{0} of {1}',
  'middle' => '{0}, {1}',
  'end' => '{0} of {1}'
};

1;

