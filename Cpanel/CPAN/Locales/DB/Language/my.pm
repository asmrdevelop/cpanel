package Cpanel::CPAN::Locales::DB::Language::my;

use strict;

#use warnings;

# Auto generated from CLDR

$Cpanel::CPAN::Locales::DB::Language::my::VERSION = '0.09';

$Cpanel::CPAN::Locales::DB::Language::my::cldr_version = '2.0';

%Cpanel::CPAN::Locales::DB::Language::my::misc_info = (
    'characters'   => { 'more_information' => "\?" },
    'cldr_formats' => {
        '_decimal_format_decimal' => "\.",
        '_decimal_format_group'   => "\,",
        '_percent_format_percent' => "\%",
        'decimal'                 => "\#\,\#\#0\.\#\#\#",
        'ellipsis'                => {
            'final'   => "\{0\}…",
            'initial' => "…\{0\}",
            'medial'  => "\{0\}…\{1\}"
        },
        'language' => "ဘာသာစကား\ \-\ \{0\}",
        'list'     => {
            2        => "\{0\}\ and\ \{1\}",
            'end'    => "\{0\}\,\ and\ \{1\}",
            'middle' => "\{0\}\,\ \{1\}",
            'start'  => "\{0\}\,\ \{1\}"
        },
        'locale'    => "\{0\}\ \(\{1\}\)",
        'percent'   => "\#\,\#\#0\%",
        'territory' => "နယ်ပယ်ဒေသ\ \-\ \{0\}"
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
        'nostr'  => 'မဟုတ်ဘူး',
        'yesstr' => 'ဟုတ်တယ်'
    },
);



#name_to_code is only generated when needed for memory
$Cpanel::CPAN::Locales::DB::Language::my::misc_info{cldr_formats}{list_or} = {
  'middle' => '{0} {1}',
  'end' => "{0} \x{e1}\x{80}\x{9e}\x{e1}\x{80}\x{ad}\x{e1}\x{80}\x{af}\x{e1}\x{80}\x{b7}\x{e1}\x{80}\x{99}\x{e1}\x{80}\x{9f}\x{e1}\x{80}\x{af}\x{e1}\x{80}\x{90}\x{e1}\x{80}\x{ba} {1}",
  '2' => "{0} \x{e1}\x{80}\x{9e}\x{e1}\x{80}\x{ad}\x{e1}\x{80}\x{af}\x{e1}\x{80}\x{b7}\x{e1}\x{80}\x{99}\x{e1}\x{80}\x{9f}\x{e1}\x{80}\x{af}\x{e1}\x{80}\x{90}\x{e1}\x{80}\x{ba} {1}",
  'start' => '{0} {1}'
};

1;

