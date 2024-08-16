package Cpanel::CPAN::Locales::DB::Language::cy;

use strict;

#use warnings;

# Auto generated from CLDR

$Cpanel::CPAN::Locales::DB::Language::cy::VERSION = '0.09';

$Cpanel::CPAN::Locales::DB::Language::cy::cldr_version = '2.0';

%Cpanel::CPAN::Locales::DB::Language::cy::misc_info = (
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
            'two',
            'few',
            'many',
            'zero',
            'other'
        ],
        'category_rules' => {
            'few'  => "n\ is\ 3",
            'many' => "n\ is\ 6",
            'one'  => "n\ is\ 1",
            'two'  => "n\ is\ 2",
            'zero' => "n\ is\ 0"
        },
        'category_rules_compiled' => {
            'few' => sub {
                if ( ( ( $_[0] == 3 ) ) ) { return 'few'; }
                return;
            },
            'many' => sub {
                if ( ( ( $_[0] == 6 ) ) ) { return 'many'; }
                return;
            },
            'one' => sub {
                if ( ( ( $_[0] == 1 ) ) ) { return 'one'; }
                return;
            },
            'two' => sub {
                if ( ( ( $_[0] == 2 ) ) ) { return 'two'; }
                return;
            },
            'zero' => sub {
                if ( ( ( $_[0] == 0 ) ) ) { return 'zero'; }
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
$Cpanel::CPAN::Locales::DB::Language::cy::misc_info{cldr_formats}{list_or} = {
  'end' => '{0} neu {1}',
  'middle' => '{0}, {1}',
  'start' => '{0}, {1}',
  '2' => '{0} neu {1}'
};

1;

