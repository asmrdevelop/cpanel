package Cpanel::CPAN::Locales::DB::Language::ksh;

use strict;

#use warnings;

# Auto generated from CLDR

$Cpanel::CPAN::Locales::DB::Language::ksh::VERSION = '0.09';

$Cpanel::CPAN::Locales::DB::Language::ksh::cldr_version = '2.0';

%Cpanel::CPAN::Locales::DB::Language::ksh::misc_info = (
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
        'language' => "de\ Schprooch\ afjekööz\ met\ „\{0\}“",
        'list'     => {
            2        => "\{0\}\ un\ \{1\}",
            'end'    => "\{0\}\ un\ \{1\}",
            'middle' => "\{0\}\,\ \{1\}",
            'start'  => "\{0\}\,\ \{1\}"
        },
        'locale'    => "\{0\}\ en\ \{1\}",
        'percent'   => "\#\,\#\#0 \%",
        'territory' => "de\ Jääjend\ afjekööz\ met\ „\{0\}“"
    },
    'delimiters' => {
        'alternate_quotation_end'   => '‘',
        'alternate_quotation_start' => '‚',
        'quotation_end'             => '“',
        'quotation_start'           => '„'
    },
    'fallback' => [
        'de_de',
        'nl',
        'nds',
        'en'
    ],
    'orientation' => {
        'characters' => "left\-to\-right",
        'lines'      => "top\-to\-bottom"
    },
    'plural_forms' => {
        'category_list' => [
            'one',
            'zero',
            'other'
        ],
        'category_rules' => {
            'one'  => "n\ is\ 1",
            'zero' => "n\ is\ 0"
        },
        'category_rules_compiled' => {
            'one' => sub {
                if ( ( ( $_[0] == 1 ) ) ) { return 'one'; }
                return;
            },
            'zero' => sub {
                if ( ( ( $_[0] == 0 ) ) ) { return 'zero'; }
                return;
            }
        }
    },
    'posix' => {
        'nostr' => {
            'content' => "nä\:nää\:näh\:n",
            'draft'   => 'unconfirmed'
        },
        'yesstr' => {
            'content' => "jo\:joh\:joo\:j",
            'draft'   => 'unconfirmed'
        }
    },
);



#name_to_code is only generated when needed for memory
$Cpanel::CPAN::Locales::DB::Language::ksh::misc_info{cldr_formats}{list_or} = {
  '2' => '{0} or {1}',
  'start' => '{0}, {1}',
  'middle' => '{0}, {1}',
  'end' => '{0}, or {1}'
};

1;

