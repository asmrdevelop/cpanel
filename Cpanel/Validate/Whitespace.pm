package Cpanel::Validate::Whitespace;

# cpanel - Cpanel/Validate/Whitespace.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::ArrayFunc::Uniq ();
use Cpanel::Exception       ();

my %ascii_codes = (
    "\x09" => 'TAB',
    "\x0a" => 'LF',
    "\x0b" => 'VT',
    "\x0c" => 'FF',
    "\x0d" => 'CR',
);

my $ascii_non_space_ws_regexp;

#i.e., the only ASCII whitespace permitted is the space character.
#
sub ascii_only_space_or_die {
    my $str = shift;

    $ascii_non_space_ws_regexp ||= '[' . join( q<>, map { quotemeta } keys %ascii_codes ) . ']';

    my @violations = ( $str =~ m<($ascii_non_space_ws_regexp)>g );
    if (@violations) {
        @violations = map { $ascii_codes{$_} } Cpanel::ArrayFunc::Uniq::uniq(@violations);

        die Cpanel::Exception::create( 'InvalidParameter', 'Remove the following whitespace [numerate,_1,character,characters]: [join,~, ,_2]', [ scalar(@violations), \@violations ] );
    }

    return 1;
}

1;
