package Cpanel::Backup::Status;

# cpanel - Cpanel/Backup/Status.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::LoadModule ();

=head1 NAME

Cpanel::Backup::Status

=head1 DESCRIPTION

Functions that return the enabled status' of the 2 backup systems.

=head2 is_legacy_backup_enabled ()

Takes no arguments.

Returns whether the legacy backup system is enabled.

=cut

sub is_legacy_backup_enabled {
    Cpanel::LoadModule::load_perl_module('Cpanel::Config::Backup');
    my %CONF = Cpanel::Config::Backup::load();
    return ( $CONF{'BACKUPENABLE'} eq 'yes' ) ? 1 : 0;
}

=head2 is_backup_enabled ()

Takes no arguments.

Returns whether the backup system is enabled.

=cut

sub is_backup_enabled {
    Cpanel::LoadModule::load_perl_module('Cpanel::Backup::Config');
    my $conf_ref = Cpanel::Backup::Config::load();
    return 0 if !$conf_ref;
    return 0 if !exists $conf_ref->{'BACKUPENABLE'};
    return ( $conf_ref->{'BACKUPENABLE'} eq 'yes' ) ? 1 : 0;
}

1;
