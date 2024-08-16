package Cpanel::CPAN::Locales::DB::Language::gv;

use strict;

#use warnings;

# Auto generated from CLDR

$Cpanel::CPAN::Locales::DB::Language::gv::VERSION = '0.09';

$Cpanel::CPAN::Locales::DB::Language::gv::cldr_version = '2.0';

%Cpanel::CPAN::Locales::DB::Language::gv::misc_info = (
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
        'language' => "Language\:\ \{0\}",
        'list'     => {
            2        => "\{0\}\ and\ \{1\}",
            'end'    => "\{0\}\,\ and\ \{1\}",
            'middle' => "\{0\}\,\ \{1\}",
            'start'  => "\{0\}\,\ \{1\}"
        },
        'locale'    => "\{0\}\ \(\{1\}\)",
        'percent'   => "\#\,\#\#0\%",
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
        'category_list' => [
            'one',
            'other'
        ],
        'category_rules'          => { 'one' => "n\ mod\ 10\ in\ 1\.\.2\ or\ n\ mod\ 20\ is\ 0" },
        'category_rules_compiled' => {
            'one' => sub {
                if ( ( ( int( $_[0] ) == $_[0] && ( ( $_[0] % 10 ) + ( $_[0] - int( $_[0] ) ) ) >= 1 && ( ( $_[0] % 10 ) + ( $_[0] - int( $_[0] ) ) ) <= 2 ) ) || ( ( ( ( $_[0] % 20 ) + ( $_[0] - int( $_[0] ) ) ) == 0 ) ) ) { return 'one'; }
                return;
            }
        }
    },
    'posix' => {
        'nostr'  => "no\:n",
        'yesstr' => "yes\:y"
    },
);



#name_to_code is only generated when needed for memory
$Cpanel::CPAN::Locales::DB::Language::gv::misc_info{cldr_formats}{list_or} = {
  'end' => '{0}, or {1}',
  'middle' => '{0}, {1}',
  'start' => '{0}, {1}',
  '2' => '{0} or {1}'
};

1;

