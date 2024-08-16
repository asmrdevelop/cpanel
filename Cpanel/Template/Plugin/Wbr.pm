package Cpanel::Template::Plugin::Wbr;

# cpanel - Cpanel/Template/Plugin/Wbr.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use base 'Template::Plugin';

use strict;

sub wbr_on_at_symbol {
    my ( $self, $string ) = @_;

    return _wbr_on_at_symbol($string);
}

sub _wbr_on_at_symbol {
    my ($string) = @_;
    $string =~ s/\@/\<wbr\>\@/g;

    return $string;
}

1;
