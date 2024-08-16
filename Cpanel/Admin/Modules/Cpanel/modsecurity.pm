#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - Cpanel/Admin/Modules/Cpanel/modsecurity.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Admin::Modules::Cpanel::modsecurity;

use strict;
use warnings;

use parent qw( Cpanel::Admin::Base );

sub _actions {
    return qw( DOMAIN_MODSEC_ENABLE DOMAIN_MODSEC_DISABLE );
}

sub DOMAIN_MODSEC_DISABLE {
    my ( $self, @domains ) = @_;
    $self->cpuser_has_feature_or_die('modsecurity');
    my $user = $self->get_caller_username();
    require Cpanel::ModSecurity::Admin;
    return Cpanel::ModSecurity::Admin::adjust_secruleengineoff(
        user    => $user,
        domains => \@domains,
        state   => 1,
        restart => 1,
    );
}

sub DOMAIN_MODSEC_ENABLE {
    my ( $self, @domains ) = @_;
    $self->cpuser_has_feature_or_die('modsecurity');
    my $user = $self->get_caller_username();
    require Cpanel::ModSecurity::Admin;
    return Cpanel::ModSecurity::Admin::adjust_secruleengineoff(
        user    => $user,
        domains => \@domains,
        state   => 0,
        restart => 1,
    );
}

1;
