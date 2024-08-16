package Cpanel::DNS::Unbound::Workarounds::Read;

# cpanel - Cpanel/DNS/Unbound/Workarounds/Read.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::DNS::Unbound::Workarounds::Config ();
use Cpanel::Autodie                           qw(exists);

=encoding utf-8

=head1 NAME

Cpanel::DNS::Unbound::Workarounds::Read - Read worksaround needed to configure unbound to work on the local system

=head1 SYNOPSIS

    use Cpanel::DNS::Unbound::Workarounds::Read;

    my $unbound = DNS::Unbound->new();

    Cpanel::DNS::Unbound::Workarounds::Read::enable_workarounds_on_unbound_object($unbound);

=head1 DESCRIPTION

This module enables various configuration options on an DNS::Unbound object
in order to allow it to function with the local systems network and firewall.

The configuration options that this module sets are represented by a directory
of flag (aka touch) files that are created by the C<Cpanel::DNS::Unbound::Workarounds>
module.

=head2 enable_workarounds_on_unbound_object($unbound)

This function will call set_option on a C<DNS::Unbound> object
based on which flags C<Cpanel::DNS::Unbound::Workarounds> detected
are needed to allow it to function on this system.

=cut

sub enable_workarounds_on_unbound_object {
    my ($unbound) = @_;

    foreach my $key ( sort keys %Cpanel::DNS::Unbound::Workarounds::Config::UNBOUND_KEYS_TO_FLAG_FILE_NAMES ) {
        if ( _flag_file_exists_for_key($key) ) {
            $unbound->set_option( $key => $Cpanel::DNS::Unbound::Workarounds::Config::UNBOUND_CONFIG_VALUES{$key} );
        }
    }

    return 1;
}

# Mocked in tests
sub _flag_file_exists_for_key {
    my ($key) = @_;
    return Cpanel::Autodie::exists("$Cpanel::DNS::Unbound::Workarounds::Config::DNS_FLAGS_DIR/$Cpanel::DNS::Unbound::Workarounds::Config::UNBOUND_KEYS_TO_FLAG_FILE_NAMES{$key}");
}

1;
