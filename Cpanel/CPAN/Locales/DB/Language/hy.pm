package Cpanel::CPAN::Locales::DB::Language::hy;

use strict;

#use warnings;

# Auto generated from CLDR

$Cpanel::CPAN::Locales::DB::Language::hy::VERSION = '0.09';

$Cpanel::CPAN::Locales::DB::Language::hy::cldr_version = '2.0';

%Cpanel::CPAN::Locales::DB::Language::hy::misc_info = (
    'characters'   => { 'more_information' => "\?" },
    'cldr_formats' => {
        '_decimal_format_decimal' => "\,",
        '_decimal_format_group'   => "\.",
        '_percent_format_percent' => "\%",
        'decimal'                 => "\#0\.\#\#\#",
        'ellipsis'                => {
            'final'   => "\{0\}…",
            'initial' => "…\{0\}",
            'medial'  => "\{0\}…\{1\}"
        },
        'language' => "Language\:\ \{0\}",
        'list'     => {
            2        => "\{0\}\ and\ \{1\}",
            'end'    => "\{0\}\,\ and\ \{1\}",
            'middle' => "\{0\}\,\ \{1\}",
            'start'  => "\{0\}\,\ \{1\}"
        },
        'locale'    => "\{0\}\ \(\{1\}\)",
        'percent'   => "\#0\%",
        'territory' => "Region\:\ \{0\}"
    },
    'delimiters' => {
        'alternate_quotation_end'   => "\â\\",
        'alternate_quotation_start' => "\â\\",
        'quotation_end'             => "\â\\",
        'quotation_start'           => "\â\\"
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
        'nostr'  => "no\:n",
        'yesstr' => "yes\:y"
    },
);



#name_to_code is only generated when needed for memory
$Cpanel::CPAN::Locales::DB::Language::hy::misc_info{cldr_formats}{list_or} = {
  'end' => "{0} \x{d5}\x{af}\x{d5}\x{a1}\x{d5}\x{b4} {1}",
  'middle' => '{0}, {1}',
  '2' => "{0} \x{d5}\x{af}\x{d5}\x{a1}\x{d5}\x{b4} {1}",
  'start' => '{0}, {1}'
};

1;
