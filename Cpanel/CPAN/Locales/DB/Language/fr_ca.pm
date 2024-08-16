package Cpanel::CPAN::Locales::DB::Language::fr_ca;

use strict;

#use warnings;

# Auto generated from CLDR

$Cpanel::CPAN::Locales::DB::Language::fr_ca::VERSION = '0.09';

$Cpanel::CPAN::Locales::DB::Language::fr_ca::cldr_version = '2.0';

%Cpanel::CPAN::Locales::DB::Language::fr_ca::misc_info = (
    'characters'   => { 'more_information' => "\?" },
    'cldr_formats' => {
        '_decimal_format_decimal' => "\,",
        '_decimal_format_group'   => ' ',
        '_percent_format_percent' => "\%",
        'decimal'                 => "\#\,\#\#0\.\#\#\#",
        'ellipsis'                => {
            'final'   => "\{0\}\.\.\.",
            'initial' => "\.\.\.\{0\}",
            'medial'  => "\{0\}\.\.\.\{1\}"
        },
        'language' => "langue\ \:\ \{0\}",
        'list'     => {
            2        => "\{0\}\ et\ \{1\}",
            'end'    => "\{0\}\ et\ \{1\}",
            'middle' => "\{0\}\,\ \{1\}",
            'start'  => "\{0\}\,\ \{1\}"
        },
        'locale'    => "\{0\}\ \(\{1\}\)",
        'percent'   => "\#\,\#\#0 \%",
        'territory' => "région\ \:\ \{0\}"
    },
    'delimiters' => {
        'alternate_quotation_end'   => '”',
        'alternate_quotation_start' => '“',
        'quotation_end'             => '»',
        'quotation_start'           => '«'
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
        'category_rules'          => { 'one' => "n\ within\ 0\.\.2\ and\ n\ is\ not\ 2" },
        'category_rules_compiled' => {
            'one' => sub {
                if ( ( ( $_[0] >= 0 && $_[0] <= 2 ) && ( $_[0] != 2 ) ) ) { return 'one'; }
                return;
            }
        }
    },
    'posix' => {
        'nostr'  => "non\:n",
        'yesstr' => "oui\:o"
    },
);



#name_to_code is only generated when needed for memory
$Cpanel::CPAN::Locales::DB::Language::fr_ca::misc_info{cldr_formats}{list_or} = {
  'middle' => '{0}, {1}',
  'end' => '{0} ou {1}',
  'start' => '{0}, {1}',
  '2' => '{0} ou {1}'
};

1;

