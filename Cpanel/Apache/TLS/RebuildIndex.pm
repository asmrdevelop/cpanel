package Cpanel::Apache::TLS::RebuildIndex;

# cpanel - Cpanel/Apache/TLS/RebuildIndex.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Apache::TLS::RebuildIndex - rebuild the Apache TLS index DB’s data

=head1 SYNOPSIS

    my $xaction = Cpanel::Apache::TLS::rebuild_all( $atls_idx );

    # … do whatever else, or nothing

    $xaction->release();

=head1 DESCRIPTION

This module implements logic to recreate records in the Apache TLS
index database based on the vhosts and certificates that
L<Cpanel::Apache::TLS> reports.

=cut

use Cpanel::Apache::TLS               ();
use Cpanel::SSL::Objects::Certificate ();

=head1 FUNCTIONS

=head2 $xaction = rebuild_all( ATLS_IDX )

Does the rebuild. ATLS_IDX is an instance of L<Cpanel::Apache::TLS::Index>.

The return value is a transaction object for that class. This is returned
so that the caller can do other write activities with the same transaction.
You’ll need to C<release()> that transaction, or the rebuild won’t be
saved.

=cut

sub rebuild_all {
    my ( $atls_idx, %opts ) = @_;

    my $xaction = $atls_idx->start_transaction('rebuild');

    local $@;

    my ( $before_cr, $after_cr ) = @opts{ 'before_each', 'after_each' };

    for my $vhname ( Cpanel::Apache::TLS->get_tls_vhosts() ) {
        $before_cr->($vhname) if $before_cr;

        eval {
            my ($cert) = Cpanel::Apache::TLS->get_certificates($vhname);
            my $obj = Cpanel::SSL::Objects::Certificate->new( cert => $cert );
            $atls_idx->set( $vhname, $obj );
        };

        if ($@) {
            warn "$vhname: $@";
        }
        elsif ($after_cr) {
            $after_cr->($vhname);
        }
    }

    return $xaction;
}

1;
