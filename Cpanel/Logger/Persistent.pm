
# cpanel - Cpanel/Logger/Persistent.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Logger::Persistent;

use strict;
use base 'Cpanel::Logger';

=head1 NAME

Cpanel::Logger::Persistent

=head1 DESCRIPTION

Works like Cpanel::Logger, except that the filehandle for the log file persists
in the object across writes. This means that when you drop privileges, you will
continue to be able to write to the file.

When running as an unprivileged user, it also adds a [uid=....] section to the log
entry. This feature is meant to help in understanding permission problems which can
arise in a process that drops privileges for part of its run.

=cut

sub new {
    my ( $class, $arg_ref ) = @_;

    $arg_ref ||= {};

    return $class->SUPER::new( { %{$arg_ref}, 'open_now' => 1 } );
}

1;
