package Cpanel::Encoder::Exim;

# cpanel - Cpanel/Encoder/Exim.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# ***** YOU MAY NOT USE A USE STATEMENT IN THIS MODULE BECAUSE IT IS CALLED FROM exim.pl *******

#Test for \x0a and \x0d explicitly because Perl changes what those mean
#across different platforms.
my %encodes = (
    q{\\}  => q{\\\\\\\\},    #\ -> \\\\
    q{"}   => q{\\"},         #" -> \"
    q{$}   => q{\\\\$},       #$ -> \\$
    "\x0a" => q{\\n},         #newline -> \n
    "\x0d" => q{\\r},         #carriage return -> \r
    "\x09" => q{\\t},         #tab => \t
);

sub encode_string_literal {
    return if !defined $_[0];

    return q{"} . join( q{}, map { $encodes{$_} || $_ } split( m{}, $_[0] ) ) . q{"};
}

sub unquoted_encode_string_literal {
    my $string = shift;
    return if !defined $string;

    $string =~ s/\\N/\\N\\\\N\\N/g;    # Only use / here for perl compat
    return "\\N$string\\N";
}

1;
