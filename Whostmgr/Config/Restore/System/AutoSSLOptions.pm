package Whostmgr::Config::Restore::System::AutoSSLOptions;

# cpanel - Whostmgr/Config/Restore/System/AutoSSLOptions.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Config::Restore::System::AutoSSLOptions

=head1 DESCRIPTION

This module is the restore-side complement to
L<Whostmgr::Config::Backup::System::AutoSSLOptions>.

This module subclasses L<Whostmgr::Config::Restore::Base::JSON>.

=cut

#----------------------------------------------------------------------

use parent qw( Whostmgr::Config::Restore::Base::JSON );

use Whostmgr::API::1::Utils::Execute ();

#----------------------------------------------------------------------

sub _restore_from_structure ( $self, $struct_hr ) {

    for my $key ( keys %$struct_hr ) {
        Whostmgr::API::1::Utils::Execute::execute_or_die(
            'SSL', 'set_autossl_metadata_key',
            {
                key   => $key,
                value => $struct_hr->{$key},
            },
        );
    }

    return;
}

1;
