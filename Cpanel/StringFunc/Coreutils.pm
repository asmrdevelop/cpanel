package Cpanel::StringFunc::Coreutils;

# cpanel - Cpanel/StringFunc/Coreutils.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::StringFunc::Coreutils - Functions for quoting/dequoting strings in a way
compliant with that used across many apps such as gtar

=head1 SYNOPSIS

    use Cpanel::StringFunc::Coreutils ();
    # Output of the following strings as a filename when seen through the output style "escape" (default for tar). `tar -tvf /path/to/tarball.tgz`
    my $string = q{\001\002\003\004\005\006\a\b\t\n\v\f\r\016\017\020\021\022\023\024\025\026\027\030\031\032\033\034\035\036\037 !"#$%&'()*+,-.0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~\177\200\201\202};
    my $original_string ="";
    for(1..130) {
        # Skip / in this example
        next if $_ == 47;
        $original_string .= chr($_);
    }
    print "Before  : “ $string ”\n";
    Cpanel::StringFunc::Coreutils::dequote($string);
    print " After  : “ $string ”\n";
    print "Compare : “ $original_string ”\n";

=cut

# Note that the gtar docs specify the DEL char ^? ( 7F or 127 or 177 depending how reference it ) however
# testing shows it encodes it as \177 octal the same as it does with many others

my %dequote = (
    'a'  => "\x07",
    'b'  => "\x08",
    't'  => "\x09",
    'n'  => "\x0a",
    'v'  => "\x0b",
    'f'  => "\x0c",
    'r'  => "\x0d",
    '\\' => q<\\>,
);

=head2 dequote( $string_ref )

Dequotes the "escape" type quoting from gtar

=over 2

=item Input

=over 4

=item I<reference> (string)

String reference containing quoted / escaped text

=back

=item Output

Modifies the string reference passed in to dequote_coreutils() directly

=back

=cut

sub dequote {
    $_[0] =~ s/\\([0-9]{3}|[abtnvfr\\])/(length($1) == 1) ? $dequote{$1} : chr(oct $1)/eg;
    return;
}
