package Cpanel::CPAN::Locales::DB::Language::nds;

use strict;

#use warnings;

# Auto generated from CLDR

$Cpanel::CPAN::Locales::DB::Language::nds::VERSION = '0.09';

$Cpanel::CPAN::Locales::DB::Language::nds::cldr_version = '2.0';

%Cpanel::CPAN::Locales::DB::Language::nds::misc_info = (
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
        'language' => "Spraak\:\ \{0\}",
        'list'     => {
            2        => "\{0\}\ and\ \{1\}",
            'end'    => "\{0\}\,\ and\ \{1\}",
            'middle' => "\{0\}\,\ \{1\}",
            'start'  => "\{0\}\,\ \{1\}"
        },
        'locale'    => "\{0\}\ \(\{1\}\)",
        'percent'   => "\#\,\#\#0 \%",
        'territory' => "Region\:\ \{0\}"
    },
    'delimiters' => {
        'alternate_quotation_end'   => '‘',
        'alternate_quotation_start' => '‚',
        'quotation_end'             => '“',
        'quotation_start'           => '„'
    },
    'fallback'    => [],
    'orientation' => {
        'characters' => "left\-to\-right",
        'lines'      => "top\-to\-bottom"
    },
    'plural_forms' => {
        'category_list'  => ['other'],
        'category_rules' => {}
    },
    'posix' => {
        'nostr' => {
            'content' => "nee\:n",
            'draft'   => 'unconfirmed'
        },
        'yesstr' => {
            'content' => "jo\:j",
            'draft'   => 'unconfirmed'
        }
    },
);



#name_to_code is only generated when needed for memory
$Cpanel::CPAN::Locales::DB::Language::nds::misc_info{cldr_formats}{list_or} = {
  '2' => '{0} or {1}',
  'start' => '{0}, {1}',
  'middle' => '{0}, {1}',
  'end' => '{0}, or {1}'
};

1;

