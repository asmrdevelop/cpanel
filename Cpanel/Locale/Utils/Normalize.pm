package Cpanel::Locale::Utils::Normalize;

# cpanel - Cpanel/Locale/Utils/Normalize.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Locale::Utils::Normalize - Quickly normalize a locale tag

=head1 SYNOPSIS

    use Cpanel::Locale::Utils::Normalize ();

    my $normalized_tag = Cpanel::Locale::Utils::Normalize::normalize_tag('en-us');

=head1 DESCRIPTION

Normalize a locale tag so it can be processed by
I18N::LangTags.  This functions the same as
Locales::normalize_tag with faster internals.

=head2 normalize_tag($tag)

Returns the normalized version of a locale tag.

Example

Input: en-US

Output: en_us

=cut

sub normalize_tag {
    my ($tag) = @_;
    return if !defined $tag;
    $tag =~ tr/A-Z/a-z/;
    $tag =~ tr{\r\n \t\f}{}d;
    if ( $tag =~ tr{a-z0-9}{}c ) {
        $tag =~ s{[^a-z0-9]+$}{};    # I18N::LangTags::locale2language_tag() does not allow trailing '_'
        $tag =~ tr{a-z0-9}{_}c;
    }

    # would like to do this with a single call, backtracking or indexing ? patches welcome!
    if ( length $tag > 8 ) {
        while ( $tag =~ s/([^_]{8})([^_])/$1\_$2/ ) { }    # I18N::LangTags::locale2language_tag() only allows parts between 1 and 8 character
    }
    return $tag;
}

1;
