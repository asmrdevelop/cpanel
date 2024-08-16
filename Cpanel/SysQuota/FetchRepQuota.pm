package Cpanel::SysQuota::FetchRepQuota;

# cpanel - Cpanel/SysQuota/FetchRepQuota.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Cpanel::Binaries ();

our $DEFAULT_QUOTA_TIMEOUT = 60;

=encoding utf-8

=head1 NAME

Cpanel::SysQuota::FetchRepQuota - A simple wrapper around the repquota command

=head1 SYNOPSIS

    use Cpanel::SysQuota::FetchRepQuota;

    $repquota_data = Cpanel::SysQuota::FetchRepQuota::fetch_repquota_with_timeout( $cpconf->{'repquota_timeout'} );

=cut

=head2 fetch_repquota_with_timeout

Run repquota -auv with a timeout

=over 2

=item Input

=over 3

=item C<SCALAR>

    A timeout for the maximum time allowed to run repquota

=back

=item Output

=over 3

=item C<SCALAR>

    The data on stdout from the repquota -auv command

=back

=back

=cut

sub fetch_repquota_with_timeout {
    my ($timeout) = @_;

    $timeout ||= $DEFAULT_QUOTA_TIMEOUT;

    my $repquota_cmd = Cpanel::Binaries::path('repquota');
    if ( !-x $repquota_cmd ) {
        die('Unable to locate repquota binary. This function cannot be used until the repquota binary is available.');
    }

    require Cpanel::SafeRun::Object;
    return Cpanel::SafeRun::Object->new_or_die(
        'timeout'      => $timeout,
        'read_timeout' => $timeout,
        'program'      => $repquota_cmd,
        'args'         => ['-auv']
    )->stdout();
}
