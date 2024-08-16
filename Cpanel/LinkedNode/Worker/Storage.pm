package Cpanel::LinkedNode::Worker::Storage;

# cpanel - Cpanel/LinkedNode/Worker/Storage.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Worker::Storage

=head1 SYNOPSIS

    my $alias_tk_ar = Cpanel::LinkedNode::Worker::Storage::read( \%cpuser, 'Mail' );

    Cpanel::LinkedNode::Worker::Storage::set( \%cpuser, 'Mail', $alias, $tk );

    Cpanel::LinkedNode::Worker::Storage::unset( \%cpuser, 'Mail' );

=head1 DESCRIPTION

This module interfaces with hash references that represent the contents
of cpuser files: it reads, sets, and unsets a user’s worker node
configuration.

=cut

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $alias_tkn_ar_or_undef = read( \%CPUSER, $TYPE )

Looks inside %CPUSER for configuration of a worker node of type $TYPE.
If found, that configuration is returned as a 2-member hash reference:
[ $alias, $token ]. If no such configuration is found, undef is
returned.

=cut

sub read {
    my ( $cpuser_hr, $worker_type ) = @_;

    my $str = $cpuser_hr->{ _get_key($worker_type) };

    return _parse($str);
}

#----------------------------------------------------------------------

=head2 set( \%CPUSER, $TYPE, $ALIAS, $TOKEN )

Updates %CPUSER to indicate $ALIAS and $TOKEN as the user’s
configuration for worker node delegation of type $TYPE.

Returns nothing.

=cut

sub set {
    my ( $cpuser_hr, $worker_type, $alias, $token ) = @_;

    $cpuser_hr->{ _get_key($worker_type) } = "$alias:$token";

    return;
}

#----------------------------------------------------------------------

=head2 unset( \%CPUSER, $TYPE )

Removes any $TYPE-type worker node configuration from %CPUSER.

Returns either the 2-member array reference as described for C<read()>
above, or undef if no such configuration existed.

=cut

sub unset {
    my ( $cpuser_hr, $worker_type ) = @_;

    return _parse( delete $cpuser_hr->{ _get_key($worker_type) } );
}

#----------------------------------------------------------------------

sub _get_key {
    my ($worker_type) = @_;

    substr( $worker_type, 0, 1 ) =~ tr<A-Z><> or do {
        die "Worker type names always begin with a capital! (given: “$worker_type”)";
    };

    # NB: Cpanel/LinkedNode/List.pm duplicates this logic a bit.
    return "WORKER_NODE-$worker_type";
}

sub _parse {
    my ($str) = @_;

    return $str ? [ split m<:>, $str, 2 ] : undef;
}

1;
