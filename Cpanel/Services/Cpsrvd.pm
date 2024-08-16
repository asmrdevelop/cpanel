package Cpanel::Services::Cpsrvd;

# cpanel - Cpanel/Services/Cpsrvd.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Kill ();

#called from test
use constant _DEFAULT_SERVICES => (
    'cpsrvd',
    'cpaneld',
    'whostmgr',
    'webmaild',
);

sub signal_users_cpsrvd_to_reload {
    my ( $user, %opts ) = @_;

    return unless $user && $user ne 'root';

    my @services = $opts{'services'} ? @{ $opts{'services'} } : _DEFAULT_SERVICES();
    die "need at least 1 service!" if !@services;

    my $regexp = join '|', map { quotemeta } @services;

    # HUP tells cpsrvd child to not process any more requests
    Cpanel::Kill::killall( 'HUP', qr/^(?:$regexp)/, undef, undef, { $user => 1 } );

    return;
}

1;
