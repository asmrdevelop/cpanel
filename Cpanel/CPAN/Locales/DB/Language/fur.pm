package Cpanel::CPAN::Locales::DB::Language::fur;

use strict;

#use warnings;

# Auto generated from CLDR

$Cpanel::CPAN::Locales::DB::Language::fur::VERSION = '0.09';

$Cpanel::CPAN::Locales::DB::Language::fur::cldr_version = '2.0';

%Cpanel::CPAN::Locales::DB::Language::fur::misc_info = (
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
        'language' => "Lenghe\:\ \{0\}",
        'list'     => {
            2        => "\{0\}\ e\ \{1\}",
            'end'    => "\{0\}\ e\ \{1\}",
            'middle' => "\{0\}\,\ \{1\}",
            'start'  => "\{0\}\,\ \{1\}"
        },
        'locale'    => "\{0\}\ \(\{1\}\)",
        'percent'   => "\#\,\#\#0\%",
        'territory' => "Regjon\:\ \{0\}"
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
        'nostr' => {
            'content' => "no\:n",
            'draft'   => 'unconfirmed'
        },
        'yesstr' => {
            'content' => "sì\:si\:s",
            'draft'   => 'unconfirmed'
        }
    },
);



#name_to_code is only generated when needed for memory
$Cpanel::CPAN::Locales::DB::Language::fur::misc_info{cldr_formats}{list_or} = {
  'start' => '{0}, {1}',
  '2' => '{0} or {1}',
  'middle' => '{0}, {1}',
  'end' => '{0}, or {1}'
};

1;

