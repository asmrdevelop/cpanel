package Cpanel::CPAN::Locales::DB::Language::th;

use strict;

#use warnings;

# Auto generated from CLDR

$Cpanel::CPAN::Locales::DB::Language::th::VERSION = '0.09';

$Cpanel::CPAN::Locales::DB::Language::th::cldr_version = '2.0';

%Cpanel::CPAN::Locales::DB::Language::th::misc_info = (
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
        'language' => "\{0\}",
        'list'     => {
            2        => "\{0\}และ\{1\}",
            'end'    => "\{0\}\ และ\{1\}",
            'middle' => "\{0\}\ \{1\}",
            'start'  => "\{0\}\ \{1\}"
        },
        'locale'    => "\{0\}\ \(\{1\}\)",
        'percent'   => "\#\,\#\#0\%",
        'territory' => "\{0\}"
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
        'nostr'  => 'ไม่ใช่',
        'yesstr' => 'ใช่'
    },
);



#name_to_code is only generated when needed for memory
$Cpanel::CPAN::Locales::DB::Language::th::misc_info{cldr_formats}{list_or} = {
  'middle' => '{0}, {1}',
  'end' => "{0} \x{e0}\x{b8}\x{ab}\x{e0}\x{b8}\x{a3}\x{e0}\x{b8}\x{b7}\x{e0}\x{b8}\x{ad} {1}",
  '2' => "{0} \x{e0}\x{b8}\x{ab}\x{e0}\x{b8}\x{a3}\x{e0}\x{b8}\x{b7}\x{e0}\x{b8}\x{ad} {1}",
  'start' => '{0}, {1}'
};

1;

