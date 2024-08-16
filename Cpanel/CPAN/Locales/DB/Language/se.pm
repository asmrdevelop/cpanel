package Cpanel::CPAN::Locales::DB::Language::se;

use strict;

#use warnings;

# Auto generated from CLDR

$Cpanel::CPAN::Locales::DB::Language::se::VERSION = '0.09';

$Cpanel::CPAN::Locales::DB::Language::se::cldr_version = '2.0';

%Cpanel::CPAN::Locales::DB::Language::se::misc_info = (
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
        'language' => "giella\:\ \{0\}",
        'list'     => {
            2        => "\{0\}\ ja\ \{1\}",
            'end'    => "\{0\}\ ja\ \{1\}",
            'middle' => "\{0\}\,\ \{1\}",
            'start'  => "\{0\}\,\ \{1\}"
        },
        'locale'    => "\{0\}\ \(\{1\}\)",
        'percent'   => "\#\,\#\#0 \%",
        'territory' => "Region\:\ \{0\}"
    },
    'delimiters' => {
        'alternate_quotation_end'   => '’',
        'alternate_quotation_start' => '’',
        'quotation_end'             => '”',
        'quotation_start'           => '”'
    },
    'fallback' => [
        'nb',
        'nn',
        'sv',
        'en'
    ],
    'orientation' => {
        'characters' => "left\-to\-right",
        'lines'      => "top\-to\-bottom"
    },
    'plural_forms' => {
        'category_list' => [
            'one',
            'two',
            'other'
        ],
        'category_rules' => {
            'one' => "n\ is\ 1",
            'two' => "n\ is\ 2"
        },
        'category_rules_compiled' => {
            'one' => sub {
                if ( ( ( $_[0] == 1 ) ) ) { return 'one'; }
                return;
            },
            'two' => sub {
                if ( ( ( $_[0] == 2 ) ) ) { return 'two'; }
                return;
            }
        }
    },
    'posix' => {
        'nostr' => {
            'content' => 'ii',
            'draft'   => 'unconfirmed'
        },
        'yesstr' => {
            'content' => 'jo',
            'draft'   => 'unconfirmed'
        }
    },
);



#name_to_code is only generated when needed for memory
$Cpanel::CPAN::Locales::DB::Language::se::misc_info{cldr_formats}{list_or} = {
  'end' => '{0}, or {1}',
  'middle' => '{0}, {1}',
  'start' => '{0}, {1}',
  '2' => '{0} or {1}'
};

1;

