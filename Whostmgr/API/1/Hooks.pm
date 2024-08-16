package Whostmgr::API::1::Hooks;

# cpanel - Whostmgr/API/1/Hooks.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Hooks::Manage ();

use constant NEEDS_ROLE => {
    delete_hook   => undef,
    edit_hook     => undef,
    list_hooks    => undef,
    reorder_hooks => undef,
};

sub delete_hook {
    my ( $args, $metadata ) = @_;

    if ( !defined $args->{'id'} ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'The delete_hook call requires that an id is defined.';
        return;
    }

    $metadata->{'result'} = Cpanel::Hooks::Manage::delete( 'id' => $args->{'id'} ) ? 1    : 0;
    $metadata->{'reason'} = $metadata->{'result'}                                  ? 'OK' : $Cpanel::Hooks::Manage::ERRORMSG;

    return;
}

sub list_hooks {
    my ( undef, $metadata ) = @_;
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return { 'categories' => Cpanel::Hooks::Manage::get_structured_hooks_list() };
}

sub edit_hook {
    my ( $args, $metadata ) = @_;

    if ( !defined $args->{'id'} ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'The edit_hook call requires that an id is defined.';
        return;
    }

    my $id = delete $args->{'id'};
    Cpanel::Hooks::Manage::edit_hook( $id, %{$args} );
    if ($Cpanel::Hooks::Manage::ERRORMSG) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $Cpanel::Hooks::Manage::ERRORMSG;
    }
    else {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
    }
    return;
}

sub reorder_hooks {
    my ( $args, $metadata ) = @_;

    if ( !defined $args->{'ids'} ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'The reorder_hooks call requires that a comma-separated list of ids is passed to it.';
        return;
    }

    my @id_list = split( ',', $args->{'ids'} );
    my $res     = Cpanel::Hooks::Manage::reorder_hooks(@id_list);

    if ($Cpanel::Hooks::Manage::ERRORMSG) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $Cpanel::Hooks::Manage::ERRORMSG;
    }
    else {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
    }
    return { 'hook_order' => $res };
}

1;
