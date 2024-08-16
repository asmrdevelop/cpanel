package Cpanel::CPAN::Locales::DB::Language::mr;

use strict;

#use warnings;

# Auto generated from CLDR

$Cpanel::CPAN::Locales::DB::Language::mr::VERSION = '0.09';

$Cpanel::CPAN::Locales::DB::Language::mr::cldr_version = '2.0';

%Cpanel::CPAN::Locales::DB::Language::mr::misc_info = (
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
        'language' => "Language\:\ \{0\}",
        'list'     => {
            2        => "\{0\}\ आणि\ \{1\}",
            'end'    => "\{0\}\ आणि\ \{1\}",
            'middle' => "\{0\}\,\ \{1\}",
            'start'  => "\{0\}\,\ \{1\}"
        },
        'locale'    => "\{0\}\ \(\{1\}\)",
        'percent'   => "\#\,\#\#\,\#\#0\%",
        'territory' => "Region\:\ \{0\}"
    },
    'delimiters' => {
        'alternate_quotation_end'   => "\"",
        'alternate_quotation_start' => "\"",
        'quotation_end'             => "\'",
        'quotation_start'           => "\'"
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
        'nostr'  => 'नाहीःना',
        'yesstr' => 'होयःहो'
    },
);



#name_to_code is only generated when needed for memory
$Cpanel::CPAN::Locales::DB::Language::mr::misc_info{cldr_formats}{list_or} = {
  'start' => '{0}, {1}',
  '2' => "{0} \x{e0}\x{a4}\x{95}\x{e0}\x{a4}\x{bf}\x{e0}\x{a4}\x{82}\x{e0}\x{a4}\x{b5}\x{e0}\x{a4}\x{be} {1}",
  'middle' => '{0}, {1}',
  'end' => "{0}, \x{e0}\x{a4}\x{95}\x{e0}\x{a4}\x{bf}\x{e0}\x{a4}\x{82}\x{e0}\x{a4}\x{b5}\x{e0}\x{a4}\x{be} {1}"
};

1;

