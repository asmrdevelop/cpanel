package Cpanel::CPAN::Locales::DB::Language::kl;

use strict;

#use warnings;

# Auto generated from CLDR

$Cpanel::CPAN::Locales::DB::Language::kl::VERSION = '0.09';

$Cpanel::CPAN::Locales::DB::Language::kl::cldr_version = '2.0';

%Cpanel::CPAN::Locales::DB::Language::kl::misc_info = (
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
        'language' => "oqaatsit\:\ \{0\}",
        'list'     => {
            2        => "\{0\}\ aamma\ \{1\}",
            'end'    => "\{0\}\,\ and\ \{1\}",
            'middle' => "\{0\}\,\ \{1\}",
            'start'  => "\{0\}\ aamma\ \{1\}"
        },
        'locale'    => "\{0\}\ \(\{1\}\)",
        'percent'   => "\#\,\#\#0 \%",
        'territory' => "nunap\ imartaa\ nunataalu\:\ \{0\}"
    },
    'delimiters' => {
        'alternate_quotation_end'   => '‹',
        'alternate_quotation_start' => '›',
        'quotation_end'             => '«',
        'quotation_start'           => '»'
    },
    'fallback' => [
        'da',
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
        'nostr' => {
            'content' => "naagga\:n",
            'draft'   => 'unconfirmed'
        },
        'yesstr' => {
            'content' => "aap\:a",
            'draft'   => 'unconfirmed'
        }
    },
);



#name_to_code is only generated when needed for memory
$Cpanel::CPAN::Locales::DB::Language::kl::misc_info{cldr_formats}{list_or} = {
  'middle' => '{0}, {1}',
  'end' => '{0}, or {1}',
  'start' => '{0}, {1}',
  '2' => '{0} or {1}'
};

1;

