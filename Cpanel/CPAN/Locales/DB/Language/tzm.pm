package Cpanel::CPAN::Locales::DB::Language::tzm;

use strict;

#use warnings;

# Auto generated from CLDR

$Cpanel::CPAN::Locales::DB::Language::tzm::VERSION = '0.09';

$Cpanel::CPAN::Locales::DB::Language::tzm::cldr_version = '2.0';

%Cpanel::CPAN::Locales::DB::Language::tzm::misc_info = (
    'characters'   => { 'more_information' => "\?" },
    'cldr_formats' => {
        '_decimal_format_decimal' => "\,",
        '_decimal_format_group'   => ' ',
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
        'category_rules'          => { 'one' => "n\ in\ 0\.\.1\ or\ n\ in\ 11\.\.99" },
        'category_rules_compiled' => {
            'one' => sub {
                if ( ( ( int( $_[0] ) == $_[0] && $_[0] >= 0 && $_[0] <= 1 ) ) || ( ( int( $_[0] ) == $_[0] && $_[0] >= 11 && $_[0] <= 99 ) ) ) { return 'one'; }
                return;
            }
        }
    },
    'posix' => {
        'nostr'  => "Uhu\:U",
        'yesstr' => "Yeh\:Y"
    },
);



#name_to_code is only generated when needed for memory
$Cpanel::CPAN::Locales::DB::Language::tzm::misc_info{cldr_formats}{list_or} = {
  '2' => '{0} or {1}',
  'start' => '{0}, {1}',
  'end' => '{0}, or {1}',
  'middle' => '{0}, {1}'
};

1;
