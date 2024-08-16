package Cpanel::LoadModule::Utils;

# cpanel - Cpanel/LoadModule/Utils.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

#----------------------------------------------------------------------
# NOTE: IMPORTANT!!!
#
# This module is included in VERY memory-sensitive contexts.

#----------------------------------------------------------------------

#NOTE: This does NOT imply anything about whether a module exists in
#Perl’s symbol table. For example, the class of a modulino script won’t
#register as “loaded” from this function because it’s not in %INC, even
#though it’s in %main::.
sub module_is_loaded {
    my $p = module_path( $_[0] );
    return 0 unless defined $p;

    # use() will leave %INC entries even if the module fails to load.
    # So we check for defined-ness rather than existence.
    return defined $INC{$p} ? 1 : 0;
}

#This also accepts a path and will no-op.
sub module_path {
    my ($module_name) = @_;

    if ( defined $module_name && length($module_name) ) {
        substr( $module_name, index( $module_name, '::' ), 2, '/' ) while index( $module_name, '::' ) > -1;
        $module_name .= '.pm' unless substr( $module_name, -3 ) eq '.pm';
    }

    return $module_name;
}

sub is_valid_module_name {
    return $_[0] =~ m/\A[A-Za-z_]\w*(?:(?:'|::)\w+)*\z/ ? 1 : 0;
}

1;
