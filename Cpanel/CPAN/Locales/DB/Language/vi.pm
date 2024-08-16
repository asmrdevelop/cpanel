package Cpanel::CPAN::Locales::DB::Language::vi;

use strict;

#use warnings;

# Auto generated from CLDR

$Cpanel::CPAN::Locales::DB::Language::vi::VERSION = '0.09';

$Cpanel::CPAN::Locales::DB::Language::vi::cldr_version = '2.0';

%Cpanel::CPAN::Locales::DB::Language::vi::misc_info = (
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
        'language' => "Ngôn\ ngữ\:\ \{0\}",
        'list'     => {
            2        => "\{0\}\ và\ \{1\}",
            'end'    => "\{0\}\ và\ \{1\}",
            'middle' => "\{0\}\,\ \{1\}",
            'start'  => "\{0\}\,\ \{1\}"
        },
        'locale'    => "\{0\}\ \(\{1\}\)",
        'percent'   => "\#\,\#\#0\%",
        'territory' => "Vùng\:\ \{0\}"
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
        'category_list'  => ['other'],
        'category_rules' => {}
    },
    'posix' => {
        'nostr' => {
            'content' => "no\:n",
            'draft'   => 'contributed'
        },
        'yesstr' => {
            'content' => "yes\:y",
            'draft'   => 'contributed'
        }
    },
);



#name_to_code is only generated when needed for memory
$Cpanel::CPAN::Locales::DB::Language::vi::misc_info{cldr_formats}{list_or} = {
  'start' => '{0}, {1}',
  '2' => "{0} ho\x{e1}\x{ba}\x{b7}c {1}",
  'end' => "{0} ho\x{e1}\x{ba}\x{b7}c {1}",
  'middle' => '{0}, {1}'
};

1;

