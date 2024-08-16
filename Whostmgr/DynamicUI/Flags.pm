package Whostmgr::DynamicUI::Flags;

# cpanel - Whostmgr/DynamicUI/Flags.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::DynamicUI::Flags

=head1 SYNOPSIS

    my %system_vars = Whostmgr::DynamicUI::Flags::get_system_variables();

=head1 DESCRIPTION

This module is a minimal implementation to deduplicate a bit of logic
that caused a bug (CPANEL-38393).

It should ideally contain much more of the logic to parse the flags
in WHM dynamicUI files.

=cut

#----------------------------------------------------------------------

use Cpanel::OS                                        ();
use Cpanel::Server::WebSocket::App::Shell::WHMDisable ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 @key_values = get_system_variables()

Returns a list of key-value pairs for the various system variables
that may appear in the dynamicUI config file.

Callers should cache this information if speed is important.

=cut

sub get_system_variables {
    my $clx = Cpanel::OS::is_cloudlinux();

    return (
        CLOUDLINUX     => $clx  ? 1 : 0,
        NOT_CLOUDLINUX => !$clx ? 1 : 0,
        terminal_ui    => !Cpanel::Server::WebSocket::App::Shell::WHMDisable->is_on(),
    );
}

1;
