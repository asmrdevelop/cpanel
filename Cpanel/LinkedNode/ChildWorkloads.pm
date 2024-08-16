package Cpanel::LinkedNode::ChildWorkloads;

# cpanel - Cpanel/LinkedNode/ChildWorkloads.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::ChildWorkloads

=head1 SYNOPSIS

    my $updated_yn = Cpanel::LinkedNode::ChildWorkloads::set('bob', 'Mail');

=head1 DESCRIPTION

This module implements logic to manipulate a user’s child-workloads
data directly. This isn’t part of normal operation; it’s something
that happens as part of out-of-band synchronization from the parent
node to child nodes.

=cut

#----------------------------------------------------------------------

use Cpanel::Config::CpUserGuard       ();
use Whostmgr::Accounts::Create::Utils ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $old_workloads_ar_or_undef = set( $USERNAME, @WORKLOADS )

Sets the indicated user as a child account that executes the
given @WORKLOADS.

@WORKLOADS B<must> contain at least one element. To unset all
workloads, call C<unset()> (see below).

Note that this does B<NOT> update the distributed-account cache
(cf. L<Cpanel::LinkedNode::AccountCache>).

Returns one of:

=over

=item * undef, to indicate that no update was needed

=item * an arrayref (possibly empty) of the old workloads

=back

The above are, notably, compatible with use in boolean context:
the account was updated if and only if the return is truthy.

=cut

sub set ( $username, @workloads ) {
    die 'Give at least one workload!' if !@workloads;

    my $workloads_str = Whostmgr::Accounts::Create::Utils::validate_child_workloads( { child_workloads => \@workloads } );

    my ( $guard, $old_workloads_str ) = _open_cpuser($username);

    if ( $old_workloads_str eq "$workloads_str" ) {
        $guard->abort();
        return undef;
    }

    $guard->{'data'}{'CHILD_WORKLOADS'} = "$workloads_str";

    $guard->save();

    return _parse_workloads_to_ar($old_workloads_str);
}

sub _parse_workloads_to_ar ($workloads_str) {
    if ( !$workloads_str ) {
        return [];
    }

    my @workloads = Whostmgr::Accounts::Create::Utils::parse_child_workloads($workloads_str);
    return \@workloads;
}

=head2 $old_workloads_ar_or_undef = unset( $USERNAME )

Clears all child workloads from a given user’s cpuser datastore.

(Equivalent to C<set($USERNAME)>, if that syntax were permissible.)

The return is the same as for C<set()> (see above).

=cut

sub unset ($username) {
    my ( $guard, $old_workloads_str ) = _open_cpuser($username);

    $guard->{'data'}{'CHILD_WORKLOADS'} = q<>;

    my $old_workloads_ar = _parse_workloads_to_ar($old_workloads_str);

    if (@$old_workloads_ar) {
        $guard->save();
    }
    else {
        $old_workloads_ar = undef;
        $guard->abort();
    }

    return $old_workloads_ar;
}

sub _open_cpuser ($username) {
    my $guard = Cpanel::Config::CpUserGuard->new("$username");

    my $old_workloads_str = $guard->{'data'}{'CHILD_WORKLOADS'} // q<>;

    return ( $guard, $old_workloads_str );
}

1;
