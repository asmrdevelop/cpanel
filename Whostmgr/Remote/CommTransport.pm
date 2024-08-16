package Whostmgr::Remote::CommTransport;

# cpanel - Whostmgr/Remote/CommTransport.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Remote::CommTransport

=head1 SYNOPSIS

    my $tls_verification = get_cpsrvd_tls_verification( $comm_transport );

=head1 DESCRIPTION

This module exposes consolidated logic for processing
the transfer system’s C<comm_transport> parameter.

=cut

#----------------------------------------------------------------------

=head1 CONSTANTS

=over

=item * C<VALUES> - A list of acceptable C<comm_transport> values.
The first-returned value is the default.

=cut

sub VALUES {
    return (
        'ssh',    # default
        'whostmgr',
        'whostmgr_insecure',
    );
}

=back

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $tv_value = get_cpsrvd_tls_verification( $COMM_TRANSPORT )

Returns a scalar, either:

=over

=item * a truthy value that should be given as
L<tls_verification>’s value to L<Whostmgr::Remote::CommandStream::Legacy>.

=item * a falsy value that indicates not to use
L<Whostmgr::Remote::CommandStream::Legacy>. (As of this writing, that means
to use SSH via L<Whostmgr::Remote>.)

=back

=cut

sub get_cpsrvd_tls_verification ($value) {
    if ( length $value ) {
        return 'on'  if $value eq 'whostmgr';
        return 'off' if $value eq 'whostmgr_insecure';

        if ( !grep { $value eq $_ } VALUES() ) {
            my @v = VALUES();
            die "Bad comm transport: $value (acceptable: @v)";
        }
    }

    return undef;
}

1;
