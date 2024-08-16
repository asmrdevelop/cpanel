package Cpanel::Server::Type::Role::SpamFilter::Change;

# cpanel - Cpanel/Server/Type/Role/SpamFilter/Change.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::Role::SpamFilter::Change - Enable and disable logic for SpamFilter services and features

=head1 SYNOPSIS

    use Cpanel::Server::Type::Role::SpamFilter::Change;

    my $role = Cpanel::Server::Type::Role::SpamFilter::Change->new();
    $role->enable();
    $role->disable();

=head1 DESCRIPTION

Subclass of C<Cpanel::Server::Type::Role::Change> that controls SpamFilter services and features

=head1 SUBROUTINES

=cut

use strict;
use warnings;

use Cpanel::Server::Type::Role::SpamFilter ();

use parent qw(
  Cpanel::Server::Type::Role::TouchFileRole::Change
);

BEGIN {
    *_NAME      = *Cpanel::Server::Type::Role::SpamFilter::_NAME;
    *_TOUCHFILE = *Cpanel::Server::Type::Role::SpamFilter::_TOUCHFILE;
}

sub _enable {
    require Whostmgr::TweakSettings;
    Whostmgr::TweakSettings::apply_module_settings( 'Main', { skipspamassassin => 0 } );
    return;
}

sub _disable {
    require Whostmgr::TweakSettings;
    Whostmgr::TweakSettings::apply_module_settings( 'Main', { skipspamassassin => 1 } );
    return;
}

1;
