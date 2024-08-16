package Cpanel::CPAN::Locales::DB::Language::lt;

use strict;

#use warnings;

# Auto generated from CLDR

$Cpanel::CPAN::Locales::DB::Language::lt::VERSION = '0.09';

$Cpanel::CPAN::Locales::DB::Language::lt::cldr_version = '2.0';

%Cpanel::CPAN::Locales::DB::Language::lt::misc_info = (
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
        'language' => "Kalba\:\ \{0\}",
        'list'     => {
            2        => "\{0\}\ ir\ \{1\}",
            'end'    => "\{0\}\ ir\ \{1\}",
            'middle' => "\{0\}\,\ \{1\}",
            'start'  => "\{0\}\,\ \{1\}"
        },
        'locale'    => "\{0\}\ \(\{1\}\)",
        'percent'   => "\#\,\#\#0 \%",
        'territory' => "Sritis\:\ \{0\}"
    },
    'delimiters' => {
        'alternate_quotation_end'   => '“',
        'alternate_quotation_start' => '„',
        'quotation_end'             => '“',
        'quotation_start'           => '„'
    },
    'fallback'    => [],
    'orientation' => {
        'characters' => "left\-to\-right",
        'lines'      => "top\-to\-bottom"
    },
    'plural_forms' => {
        'category_list' => [
            'one',
            'few',
            'other'
        ],
        'category_rules' => {
            'few' => "n\ mod\ 10\ in\ 2\.\.9\ and\ n\ mod\ 100\ not\ in\ 11\.\.19",
            'one' => "n\ mod\ 10\ is\ 1\ and\ n\ mod\ 100\ not\ in\ 11\.\.19"
        },
        'category_rules_compiled' => {
            'few' => sub {
                if ( ( ( int( $_[0] ) == $_[0] && ( ( $_[0] % 10 ) + ( $_[0] - int( $_[0] ) ) ) >= 2 && ( ( $_[0] % 10 ) + ( $_[0] - int( $_[0] ) ) ) <= 9 ) && ( int( $_[0] ) != $_[0] || ( ( $_[0] % 100 ) + ( $_[0] - int( $_[0] ) ) ) < 11 || ( ( $_[0] % 100 ) + ( $_[0] - int( $_[0] ) ) ) > 19 ) ) ) { return 'few'; }
                return;
            },
            'one' => sub {
                if ( ( ( ( ( $_[0] % 10 ) + ( $_[0] - int( $_[0] ) ) ) == 1 ) && ( int( $_[0] ) != $_[0] || ( ( $_[0] % 100 ) + ( $_[0] - int( $_[0] ) ) ) < 11 || ( ( $_[0] % 100 ) + ( $_[0] - int( $_[0] ) ) ) > 19 ) ) ) { return 'one'; }
                return;
            }
        }
    },
    'posix' => {
        'nostr'  => "ne\:n",
        'yesstr' => "taip\:t"
    },
);



#name_to_code is only generated when needed for memory
$Cpanel::CPAN::Locales::DB::Language::lt::misc_info{cldr_formats}{list_or} = {
  'middle' => '{0}, {1}',
  'end' => '{0} ar {1}',
  'start' => '{0}, {1}',
  '2' => '{0} ar {1}'
};

1;

