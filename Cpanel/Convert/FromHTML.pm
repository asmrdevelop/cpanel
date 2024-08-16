package Cpanel::Convert::FromHTML;

# cpanel - Cpanel/Convert/FromHTML.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule ();

=head1 NAME

Cpanel::Convert::FromHTML

=head1 DESCRIPTION

Provides functions for converting text from HTML into other formats. Only plaintext is supported at the moment.

=head1 SYNOPSIS

my $text_document = Cpanel::Convert::FromHTML::to_text( $html_document );

=head1 SUBROUTINES

=over

=item to_text( $html_document )

Accepts a string containing HTML markup and returns a plaintext string with the HTML removed. The returned string is always in UTF-8.

Internally the function uses the HTML::FormatText CPAN module.

=back

=cut

our $FAUX_LINE_WRAP_SUPPRESSION = 5_000;

sub to_text {
    my ($html_payload) = @_;

    Cpanel::LoadModule::load_perl_module('HTML::FormatText');
    Cpanel::LoadModule::load_perl_module('Cpanel::UTF8::Strict');

    my $text_payload = HTML::FormatText->format_string(

        #Without this we get warnings from HTML::Parser like:
        #
        #Parsing of undecoded UTF-8 will give garbage when decoding entities
        #
        Cpanel::UTF8::Strict::decode($html_payload),

        leftmargin => 0,

        #HTML::FormatText doesn't seem to expose a way to
        #suppress line wrapping, so set this to something
        #"ridiculously" high to achieve the effect:
        rightmargin => $FAUX_LINE_WRAP_SUPPRESSION,
    );

    # HTML::FormatText::end is going to add an extra unwanted newline
    chomp($text_payload);

    #Without this we get "wide character in print" warnings. (Yeesh!)
    utf8::encode($text_payload);
    return $text_payload;
}

1;
