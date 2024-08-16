package Cpanel::Template::Plugin::CPMath;

# cpanel - Cpanel/Template/Plugin/CPMath.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use base 'Template::Plugin';
use Cpanel::Math;

sub load {
    my ( $class, $context ) = @_;

    $context->define_vmethod( 'scalar', 'ceil',  \&Cpanel::Math::ceil );
    $context->define_vmethod( 'scalar', 'floor', \&Cpanel::Math::floor );
    $context->define_vmethod( 'scalar', 'int',   sub { return int shift } );

    return $class;
}

sub ceil  { shift; return Cpanel::Math::ceil( shift() ); }
sub floor { shift; return Cpanel::Math::floor( shift() ); }
sub rand  { shift; return rand shift(); }
sub int   { shift; return int shift(); }

1;
