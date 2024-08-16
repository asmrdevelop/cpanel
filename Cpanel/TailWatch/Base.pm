package Cpanel::TailWatch::Base;

# cpanel - Cpanel/TailWatch/Base.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

sub internal_name {
    return 'base';
}

sub is_enabled {
    my ( $my_ns, $tailwatch_obj ) = @_;
    return if $tailwatch_obj->has_chkservd_disable_file( $my_ns->internal_name() );
    return if $tailwatch_obj->is_skipped_in_cpconf( $my_ns->internal_name() );
    return 1;
}

sub enable {
    my ( $tailwatch_obj, $my_ns ) = @_;

    # respect verbose flag
    return if !$tailwatch_obj->remove_chksrvd_disable_files( $my_ns->internal_name() );
    return if !$tailwatch_obj->update_cpconf( { 'skip' . $my_ns->internal_name() => 0 } );
    return 1;
}

sub disable {
    my ( $tailwatch_obj, $my_ns ) = @_;

    # respect verbose flag
    return if !$tailwatch_obj->update_cpconf( { 'skip' . $my_ns->internal_name() => 1 } );

    return 1;
}

1;
