package Cpanel::Locale::Utils::Phrase;

# cpanel - Cpanel/Locale/Utils/Phrase.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# This module is a utility for development tools to employ,
# there is no practical purpose to use this in production code.

use Cpanel ();

my $pipe_delimited_keys;

sub has_acceptable_vars {
    my ( $lh, $phrase ) = @_;
    $pipe_delimited_keys ||= join( '|', sort keys %Cpanel::Grapheme );

    # no need to support/parse quotes beyond: none, single, or double
    return 1 if $phrase =~ m/\$Cpanel\::Grapheme\{\s*(['"]|)(?:$pipe_delimited_keys)\1\s*\}/;
    return;
}

sub interpolate_acceptable_vars {
    my ( $lh, $phrase ) = @_;
    $pipe_delimited_keys ||= join( '|', sort keys %Cpanel::Grapheme );

    # no need to support/parse quotes beyond: none, single, or double
    $phrase =~ s/
        \$Cpanel\::Grapheme                # variable and namespace
            \{\s*                           # opening { and possible trailing space
                (['"]|)                    # open single, double, or no quote
                    ($pipe_delimited_keys) # capture the actual key
                \1                         # closing quote (if any) that we saw earlier
            \s*\}                           # closing } and possible preceding space
    /$Cpanel::Grapheme{$2}/gx;

    return $phrase;
}

1;
