#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - Cpanel/Admin/Modules/Cpanel/emailstats.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Admin::Modules::Cpanel::emailstats;

use strict;
use warnings;

use Try::Tiny;

use parent qw( Cpanel::Admin::Base );

use Cpanel::Exception             ();
use Cpanel::EximStats::DB::Sqlite ();

#----------------------------------------------------------------------

sub _actions {
    my ($self) = @_;

    return (
        'GET_STATUS',
    );
}

#overridden in tests
BEGIN {
    *_get_status = *Cpanel::EximStats::DB::Sqlite::get_status;
}

sub GET_STATUS {
    my ($self) = @_;

    my ($status);
    try {

        #There’s no good reason to pass back the other parts of this hash,
        #though an unprivileged user can actually read the filesystem and
        #get that information. Still, there’s no reason to make it easy.
        $status = _get_status()->{'status'};
    }
    catch {
        $self->_die_generic($_);
    };

    return $status;
}

sub _die_generic {
    my ( $self, $exc ) = @_;

    if ($exc) {
        require Cpanel::Debug;
        Cpanel::Debug::log_warn("$exc");
    }

    my $err = Cpanel::Exception::create('GenericForUser');

    $err->set_id( $exc->id() ) if try { $exc->id() };

    die $err;
}

1;
