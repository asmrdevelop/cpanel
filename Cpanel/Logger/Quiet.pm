package Cpanel::Logger::Quiet;

# cpanel - Cpanel/Logger/Quiet.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use base 'Cpanel::Logger';

=head1 NAME

Cpanel::Logger::Quiet

=head1 DESCRIPTION

Works like Cpanel::Logger, except the STDOUT and STDERR output is always suppressed.

=cut

sub _get_configuration_for_logger {
    my ( $self, $cfg_or_msg ) = @_;

    my $hr = $self->SUPER::_get_configuration_for_logger($cfg_or_msg);

    $hr->{'output'} = 0;

    return $hr;
}

1;
