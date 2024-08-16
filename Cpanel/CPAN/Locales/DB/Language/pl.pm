package Cpanel::CPAN::Locales::DB::Language::pl;

use strict;

#use warnings;

# Auto generated from CLDR

$Cpanel::CPAN::Locales::DB::Language::pl::VERSION = '0.09';

$Cpanel::CPAN::Locales::DB::Language::pl::cldr_version = '2.0';

%Cpanel::CPAN::Locales::DB::Language::pl::misc_info = (
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
        'language' => "Język\:\ \{0\}",
        'list'     => {
            2        => "\{0\}\ i\ \{1\}",
            'end'    => "\{0\}\ i\ \{1\}",
            'middle' => "\{0\}\;\ \{1\}",
            'start'  => "\{0\}\;\ \{1\}"
        },
        'locale'    => "\{0\}\ \(\{1\}\)",
        'percent'   => "\#\,\#\#0\%",
        'territory' => "Region\:\ \{0\}"
    },
    'delimiters' => {
        'alternate_quotation_end'   => '”',
        'alternate_quotation_start' => '„',
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
            'few',
            'many',
            'other'
        ],
        'category_rules' => {
            'few'  => "n\ mod\ 10\ in\ 2\.\.4\ and\ n\ mod\ 100\ not\ in\ 12\.\.14",
            'many' => "n\ is\ not\ 1\ and\ n\ mod\ 10\ in\ 0\.\.1\ or\ n\ mod\ 10\ in\ 5\.\.9\ or\ n\ mod\ 100\ in\ 12\.\.14",
            'one'  => "n\ is\ 1"
        },
        'category_rules_compiled' => {
            'few' => sub {
                if ( ( ( int( $_[0] ) == $_[0] && ( ( $_[0] % 10 ) + ( $_[0] - int( $_[0] ) ) ) >= 2 && ( ( $_[0] % 10 ) + ( $_[0] - int( $_[0] ) ) ) <= 4 ) && ( int( $_[0] ) != $_[0] || ( ( $_[0] % 100 ) + ( $_[0] - int( $_[0] ) ) ) < 12 || ( ( $_[0] % 100 ) + ( $_[0] - int( $_[0] ) ) ) > 14 ) ) ) { return 'few'; }
                return;
            },
            'many' => sub {
                if (   ( ( $_[0] != 1 ) && ( int( $_[0] ) == $_[0] && ( ( $_[0] % 10 ) + ( $_[0] - int( $_[0] ) ) ) >= 0 && ( ( $_[0] % 10 ) + ( $_[0] - int( $_[0] ) ) ) <= 1 ) )
                    || ( ( int( $_[0] ) == $_[0] && ( ( $_[0] % 10 ) +  ( $_[0] - int( $_[0] ) ) ) >= 5  && ( ( $_[0] % 10 ) +  ( $_[0] - int( $_[0] ) ) ) <= 9 ) )
                    || ( ( int( $_[0] ) == $_[0] && ( ( $_[0] % 100 ) + ( $_[0] - int( $_[0] ) ) ) >= 12 && ( ( $_[0] % 100 ) + ( $_[0] - int( $_[0] ) ) ) <= 14 ) ) ) {
                    return 'many';
                }
                return;
            },
            'one' => sub {
                if ( ( ( $_[0] == 1 ) ) ) { return 'one'; }
                return;
            }
        }
    },
    'posix' => {
        'nostr'  => "nie\:n",
        'yesstr' => "tak\:t"
    },
);



#name_to_code is only generated when needed for memory
$Cpanel::CPAN::Locales::DB::Language::pl::misc_info{cldr_formats}{list_or} = {
  '2' => '{0} lub {1}',
  'start' => '{0}, {1}',
  'end' => '{0} lub {1}',
  'middle' => '{0}, {1}'
};

1;

