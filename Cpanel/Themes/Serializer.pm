package Cpanel::Themes::Serializer;

# cpanel - Cpanel/Themes/Serializer.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Exception  ();
use Cpanel::LoadModule ();

#$user is optional. If provided, the return will include integration links.
#
sub get_serializer_obj {
    my ( $format, $docroot, $user ) = @_;

    if ( $format !~ /^[a-z0-9]+$/i ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid name for a theme serializer.', [$format] );
    }

    my $module = "Cpanel::Themes::Serializer::$format";

    #This will die() if we can't load the module.
    Cpanel::LoadModule::load_perl_module($module);

    #Previously there were checks to see if the new() method exists.
    #If that happens, though, that's a (big!) programmer error,
    #so we want an "ugly", unlocalized exception in that case.
    return $module->new( 'docroot' => $docroot, 'user' => $user );
}

1;
