package Cpanel::CPAN::Locales::DB::Language::ml;

use strict;

#use warnings;

# Auto generated from CLDR

$Cpanel::CPAN::Locales::DB::Language::ml::VERSION = '0.09';

$Cpanel::CPAN::Locales::DB::Language::ml::cldr_version = '2.0';

%Cpanel::CPAN::Locales::DB::Language::ml::misc_info = (
    'characters'   => { 'more_information' => "\?" },
    'cldr_formats' => {
        '_decimal_format_decimal' => "\.",
        '_decimal_format_group'   => "\,",
        '_percent_format_percent' => "\%",
        'decimal'                 => "\#\,\#\#\,\#\#0\.\#\#\#",
        'ellipsis'                => {
            'final'   => "\{0\}…",
            'initial' => "…\{0\}",
            'medial'  => "\{0\}…\{1\}"
        },
        'language' => "ഭാഷ\:\ \{0\}",
        'list'     => {
            2        => "\{0\}\ കൂടാതെ\ \{1\}",
            'end'    => "\{0\}\,\ \{1\}\ എന്നിവ",
            'middle' => "\{0\}\,\ \{1\}",
            'start'  => "\{0\}\,\ \{1\}"
        },
        'locale'    => "\{0\}\ \(\{1\}\)",
        'percent'   => "\#\,\#\#\,\#\#0\%",
        'territory' => "ദേശം\:\ \{0\}"
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
        'nostr'  => 'അല്ല',
        'yesstr' => 'അതെ'
    },
);



#name_to_code is only generated when needed for memory
$Cpanel::CPAN::Locales::DB::Language::ml::misc_info{cldr_formats}{list_or} = {
  'middle' => "{0}, {1} \x{e0}\x{b4}\x{8e}\x{e0}\x{b4}\x{a8}\x{e0}\x{b5}\x{8d}\x{e0}\x{b4}\x{a8}\x{e0}\x{b4}\x{bf}\x{e0}\x{b4}\x{b5}",
  'end' => "{0}, \x{e0}\x{b4}\x{85}\x{e0}\x{b4}\x{b2}\x{e0}\x{b5}\x{8d}\x{e0}\x{b4}\x{b2}\x{e0}\x{b5}\x{86}\x{e0}\x{b4}\x{99}\x{e0}\x{b5}\x{8d}\x{e0}\x{b4}\x{95}\x{e0}\x{b4}\x{bf}\x{e0}\x{b5}\x{bd} {1}",
  'start' => "{0}, {1} \x{e0}\x{b4}\x{8e}\x{e0}\x{b4}\x{a8}\x{e0}\x{b5}\x{8d}\x{e0}\x{b4}\x{a8}\x{e0}\x{b4}\x{bf}\x{e0}\x{b4}\x{b5}",
  '2' => "{0} \x{e0}\x{b4}\x{85}\x{e0}\x{b4}\x{b2}\x{e0}\x{b5}\x{8d}\x{e0}\x{b4}\x{b2}\x{e0}\x{b5}\x{86}\x{e0}\x{b4}\x{99}\x{e0}\x{b5}\x{8d}\x{e0}\x{b4}\x{95}\x{e0}\x{b4}\x{bf}\x{e0}\x{b5}\x{bd} {1}"
};

1;

