package Cpanel::SpriteGen;

# cpanel - Cpanel/SpriteGen.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::ExtPerlMod ();

our $VERSION = '1.0';

sub SpriteGen_init { }

sub generate {
    my %ARGS = @_;
    return Cpanel::ExtPerlMod::func(
        'Cpanel::SpriteGen_ExtPerlMod::generate',
        {
            'fileslist'         => $ARGS{'fileslist'},
            'spriteformat'      => $ARGS{'spriteformat'},
            'spritecompression' => $ARGS{'spritecompression'},
            'spritefile'        => $ARGS{'spritefile'},
            'spritetype'        => $ARGS{'spritetype'},
            'spritemethod'      => $ARGS{'spritemethod'},
        }
    );

}

1;
