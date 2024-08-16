package Cpanel::StringFunc::HTML;

# cpanel - Cpanel/StringFunc/HTML.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::StringFunc::HTML - Tools for removing HTML from strings

=head1 SYNOPSIS

    use Cpanel::StringFunc::HTML ();

    Cpanel::StringFunc::HTML::trim_html(\$string);

=head1 DESCRIPTION

Limited removal of HTML from a string.  This should only be used to
clean up HTML and is not a security measure.

Use Cpanel::Encoder::Tiny::safe_html_encode_str() for security
measures.

=cut

my %entities = (    #Just some of the most common ones, of course
    'ldquo'  => q{"},
    'rdguo'  => q{"},
    'lsquo'  => q{`},
    'rsquo'  => q{'},
    'laquo'  => q{"},
    'raquo'  => q{"},
    'lsaquo' => q{'},
    'rsaquo' => q{'},
    'lt'     => '<',
    'gt'     => '>',
    'amp'    => '&',
    'bull'   => '*',
    'trade'  => '(TM)',
    'copy'   => '(C)',
    'reg'    => '(R)',
    'mdash'  => '---',
    'ndash'  => '--',
    'nbsp'   => ' ',
    'sup2'   => '(2)',
    'sup3'   => '(3)',
    'frac14' => '1/4',
    'frac12' => '1/2',
    'frac34' => '3/4',
);

=head2 trim_html(\$scalar)

Remove limited amount of HTML from a string in order to have
it format well as plain text.

Consider using HTML::FormatText instead.

=cut

sub trim_html {
    my $this   = shift;
    my $string = ref $this eq 'SCALAR' ? $this : \$this;

    if ( ${$string} !~ tr/<>// ) {    # If there is no html, we return ASIS
        ${$string} = _replace_html_entities( ${$string} );
        return ${$string};
    }

    ${$string} =~ s{<script.*?>.*?</script\s*>}{}msig;

    #
    # Begin <a/pre/br/p> detection and conversion
    #
    my $stream = ${$string};
    my ( $html_tag, $data_before_tag );
    my $in_pre          = 0;
    my $filtered_output = '';
    while ( $stream =~ m/(\<[^\>\<]+\>?)/ ) {
        $html_tag        = $1;
        $data_before_tag = substr( substr( $stream, 0, $+[0], '' ), 0, -1 * length($html_tag) );
        if ($in_pre) {
            $filtered_output .= $data_before_tag;
        }
        else {
            $data_before_tag =~ s{[\r\n]}{ }g;
            $data_before_tag =~ s{\s+}{ }g;
            $data_before_tag =~ s{\A\s+}{}g;

            # Preserve space before anchor tags.
            if ( $html_tag !~ /^<\s*a[^a-z]/i ) {
                $data_before_tag =~ s{\s+\z}{}g;
            }

            $filtered_output .= $data_before_tag;
        }

        if    ( $html_tag =~ m{^<\s*pre[^a-z]}i )           { $in_pre = 1; }
        elsif ( $html_tag =~ m{^<\s*\/\s*pre[^a-z]}i )      { $in_pre = 0; }
        elsif ( $html_tag =~ /<\s*[p|br][^a-z]/i )          { $filtered_output .= "\n"; }
        elsif ( $html_tag =~ /<\s*blockquote[^a-z]/i )      { $filtered_output .= "\t"; }
        elsif ( $html_tag =~ /<\s*\/\s*blockquote[^a-z]/i ) { $filtered_output .= "\n"; }
    }
    if ( pos $stream ) {
        substr( $stream, 0, pos($stream), '' );
    }
    if ($stream) {
        if ($in_pre) {
            $filtered_output .= $stream;
        }
        else {
            $stream =~ s{[\r\n]}{ }g;
            $stream =~ s{\s+}{ }g;

            # Preserve trailing space after anchor tags.
            if ( $html_tag !~ /<\s*\/\s*a[^a-z]/i ) {
                $stream =~ s{\A\s+}{ }g;
            }

            $stream =~ s{\s+\z}{}g;
            $filtered_output .= $stream;
        }
    }
    ${$string} = $filtered_output;

    #
    # End <a/pre/br/p> detection and conversion
    #

    ${$string} =~ s/<[^>]+>//g;
    ${$string} = _replace_html_entities( ${$string} );

    return ${$string};
}

sub _replace_html_entities {
    my $arg    = shift;
    my $string = ref $arg eq "SCALAR" ? $arg : \$arg;
    ${$string} =~ s/(&(\w+);)/ $entities{ lc $2 } || $1 /ieg;
    return ${$string};
}

1;
