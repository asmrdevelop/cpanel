package Whostmgr::Transfers::Session::Items::AccountRemoteBase;

# cpanel - Whostmgr/Transfers/Session/Items/AccountRemoteBase.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings) -- not fully vetted for warnings

use base 'Whostmgr::Transfers::Session::Items::AccountBase';

sub _remove_local_cpmove_files {
    my ($self) = @_;

    my $cpmove_file = ( $self->{'input'}->{'copypoint'} ? "$self->{'input'}->{'copypoint'}/$self->{'input'}->{'cpmovefile'}" : $self->{'input'}->{'cpmovefile'} );

    print $self->_locale()->maketext( 'Removing copied archive “[_1]” from the local server …', $cpmove_file ) . "\n";

    require File::Path;
    File::Path::remove_tree( $cpmove_file, { error => \my $err } );

    if ($err) {
        for my $e (@$err) {
            my ( $file, $msg ) = %$e;
            return ( 0, $msg ) if $file eq $cpmove_file;
        }
    }

    return ( 1, 'ok' );
}

1;
