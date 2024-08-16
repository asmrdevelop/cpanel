package Cpanel::CPAN::Locales::DB::Language::nn;

use strict;

#use warnings;

# Auto generated from CLDR

$Cpanel::CPAN::Locales::DB::Language::nn::VERSION = '0.09';

$Cpanel::CPAN::Locales::DB::Language::nn::cldr_version = '2.0';

%Cpanel::CPAN::Locales::DB::Language::nn::misc_info = (
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
        'language' => "Språk\:\ \{0\}",
        'list'     => {
            2        => "\{0\}\ og\ \{1\}",
            'end'    => "\{0\}\ og\ \{1\}",
            'middle' => "\{0\}\,\ \{1\}",
            'start'  => "\{0\}\,\ \{1\}"
        },
        'locale'    => "\{0\}\ \(\{1\}\)",
        'percent'   => "\#\,\#\#0 \%",
        'territory' => "Område\:\ \{0\}"
    },
    'delimiters' => {
        'alternate_quotation_end'   => '”',
        'alternate_quotation_start' => '“',
        'quotation_end'             => '»',
        'quotation_start'           => '«'
    },
    'fallback' => [
        'nb',
        'da',
        'sv',
        'en'
    ],
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
        'nostr'  => "nei\:n",
        'yesstr' => "ja\:j"
    },
);

#name_to_code is only generated when needed for memory
$Cpanel::CPAN::Locales::DB::Language::nn::misc_info{cldr_formats}{list_or} = {
  'middle' => '{0}, {1}',
  'end' => '{0}, or {1}',
  'start' => '{0}, {1}',
  '2' => '{0} or {1}'
};

1;

