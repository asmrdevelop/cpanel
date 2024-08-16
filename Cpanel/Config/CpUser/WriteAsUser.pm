package Cpanel::Config::CpUser::WriteAsUser;

# cpanel - Cpanel/Config/CpUser/WriteAsUser.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Config::CpUser::WriteAsUser

=head1 SYNOPSIS

    Cpanel::Config::CpUser::WriteAsUser::write(
        SETTING1 => 'value1',
        SETTING2 => 'value2',
    );

=head1 DESCRIPTION

This module helps to keep the cpuser file in sync with the current
process’s caches. See function descriptions for details.

=cut

#----------------------------------------------------------------------

use Cpanel::AdminBin::Call ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 write( %NEW_SETTINGS )

Writes one or more new values to the current user’s cpuser file
and updates the current process’s global variables (e.g.,
C<%Cpanel::CPDATA>) accordingly.

=cut

sub write (%key_values) {

    for my $key ( keys %key_values ) {
        Cpanel::AdminBin::Call::call( 'Cpanel', 'cpuser', 'SET', %key_values{$key} );
        $Cpanel::CPDATA{$key} = $key_values{$key};
    }

    return;
}

1;
