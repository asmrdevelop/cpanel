package Cpanel::LinkedNode::QuotaBalancer::Model;

# cpanel - Cpanel/LinkedNode/QuotaBalancer/Model.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::QuotaBalancer::Model

=head1 DESCRIPTION

This module houses the quota balancer’s computation logic.
It ultimately determines what a given user’s quotas on all
the relevant nodes should be.

Note that none of its methods that accept or return numbers assume a
unit. This is because the intent of this module is to apply to either
blocks or inodes quotas equally; in fact, the quota-balancer probably
needs to manage two separate instances of this class: one for blocks,
and another for inodes.

=cut

#----------------------------------------------------------------------

use Carp       ();
use List::Util ();

use constant {

    # Don’t balance until usage is at least 90%.
    THRESHOLD_TO_START_BALANCING => 0.9,

    # Update the balance if the target quota is a change of at least
    # 5% of their total quota.
    THRESHOLD_TO_UPDATE_BALANCE => 0.05,
};

our $_LOCAL_ALIAS;

BEGIN {
    $_LOCAL_ALIAS = q</>;
}

our ( $a, $b );

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new( $UNIT )

Instantiates this class. $UNIT is a purely-informational string inserted
into debug output, intended to help disambiguate multiple concurrent
instances of this class (e.g., one for bytes, the other for inodes).

=cut

sub new ( $class, $unit ) {
    my %self = ( _unit => $unit );

    return bless \%self, $class;
}

#----------------------------------------------------------------------

=head2 $alias_hr = I<OBJ>->compute_user_limits( $USERNAME )

Computes new limits for each of the user’s nodes. The return
is a reference to a hash, each of whose keys is either a worker alias
or empty-string for the controller node. The hash values are the usage
quota to set.

For example, a user w/ quota of 1,000 where 25% of the disk usage is on
a remote Mail worker would return:

    {
        '/' => 750,             # local/controller
        'mailworker' => 250,
    }

=cut

sub compute_user_limits ( $self, $username ) {
    return $self->{'_computed'}{$username}{'used'}{'limit'} ||= do {
        my $limit = $self->{'limit'}{$username} or die "Need local $self->{'_unit'} limit for $username";

        my $local_hr = $self->{'local'}{$username} or die "Need local $self->{'_unit'} data for $username";

        my @remote_aliases = @{ $self->get_user_worker_aliases($username) };

        if ( !@remote_aliases ) {
            die "$username: no workers??";
        }

        my %alias_usage = map { ( $_ => $self->{'remote'}{$_}{$username}{'used'} ) } @remote_aliases;

        my $total_usage = List::Util::sum( $local_hr->{'used'}, values %alias_usage );

        my $total_usage_frac = $total_usage / $limit;

        my %node_limit;

        if ( $total_usage_frac > THRESHOLD_TO_START_BALANCING ) {
            for my $alias (@remote_aliases) {
                $node_limit{$alias} = $alias_usage{$alias} / $total_usage;
            }

            $_ = int( $_ * $limit ) for values %node_limit;

            my $remote_limits_total = List::Util::sum( values %node_limit );

            $node_limit{$_LOCAL_ALIAS} = $limit - $remote_limits_total;
        }
        else {
            $node_limit{$_} = $limit for ( $_LOCAL_ALIAS, @remote_aliases );
        }

        \%node_limit;
    };
}

#----------------------------------------------------------------------

=head2 $needs_update_yn = I<OBJ>->user_needs_update( $USERNAME )

Indicates via a boolean whether $USERNAME’s quotas need to be rebalanced.

By the time this is called, $USERNAME’s data should be fully populated here.
So if it’s found that the internal data for $USERNAME is incomplete, an
exception is thrown.

=cut

sub user_needs_update ( $self, $username ) {
    my $new_limits = $self->compute_user_limits($username);

    my %old_limits = (
        $_LOCAL_ALIAS => $self->{'local'}{$username}{'limit'} // do {
            die "$username $self->{'_unit'} local limit is unset!";
        },
    );

    my $total_limit = $self->get_user_limit($username) // do {
        die "$username $self->{'_unit'} total limit is unset!";
    };

    my $currently_balanced = ( $total_limit != $old_limits{$_LOCAL_ALIAS} );

    my $need_balancing = ( $total_limit != $new_limits->{$_LOCAL_ALIAS} );

    # We need an update if we’re switching between balanced/non-blanced.
    return 1 if !!$need_balancing ne !!$currently_balanced;

    for my $alias ( keys %$new_limits ) {
        my $old_limit = $old_limits{$alias};

        $old_limit //= $self->{'remote'}{$alias}{$username}{'limit'} // do {
            die "“$username” lacks $self->{'_unit'} limit on $alias!";
        };

        my $diff = abs( $old_limit - $new_limits->{$alias} );

        if ( ( $diff / $total_limit ) > THRESHOLD_TO_UPDATE_BALANCE ) {
            return 1;
        }
    }

    return 0;
}

#----------------------------------------------------------------------

=head2 $count = I<OBJ>->get_user_limit( $USERNAME )

Returns $USERNAME’s limit as stored in the object, or undef
if no such limit is stored.

=cut

sub get_user_limit ( $self, $username ) {
    return $self->{'limit'}{$username};
}

#----------------------------------------------------------------------

=head2 $usernames_ar = I<OBJ>->get_remote_usernames( $ALIAS ) {

Returns a reference to an array that holds all the usernames associated
with $ALIAS in I<OBJ>.

=cut

sub get_remote_usernames ( $self, $alias ) {
    return [ keys %{ $self->{'remote'}{$alias} } ];
}

#----------------------------------------------------------------------

=head2 $aliases_ar = I<OBJ>->get_user_worker_aliases( $USERNAME ) {

Returns a reference to an array that holds aliases of all of
$USERNAME’s worker nodes.

=cut

sub get_user_worker_aliases ( $self, $username ) {
    my @remote_aliases = sort keys %{ $self->{'remote'} };

    my @user_worker_aliases = grep { $self->{'remote'}{$_}{$username} } @remote_aliases;

    return \@user_worker_aliases;
}

#----------------------------------------------------------------------

=head2 $obj = I<OBJ>->set_user_limit( $USERNAME, $BLOCKS )

Tells I<OBJ> the user’s total limit. Returns I<OBJ>.

This will throw if $BLOCKS is falsy because we shouldn’t get this far
if $USERNAME lacks a quota.

=cut

sub set_user_limit ( $self, $username, $num ) {
    $self->{'limit'}{$username} = $num or die "$username has unlimited $self->{'_unit'} quota?";

    return $self;
}

#----------------------------------------------------------------------

=head2 Local Getters/Setters

The following methods all relate to
properties of the user’s local account:

=over

=item * I<OBJ>->get_local_user_used( $USERNAME )

=item * I<OBJ>->get_local_user_limit( $USERNAME )

=item * I<OBJ>->set_local_user_used( $USERNAME, $COUNT )

=item * I<OBJ>->set_local_user_limit( $USERNAME, $COUNT )

=back

=cut

sub get_local_user_used ( $self, $username ) {
    return $self->{'local'}{$username}{'used'} // _fail_undef();
}

sub get_local_user_limit ( $self, $username ) {
    return $self->{'local'}{$username}{'limit'} // _fail_undef();
}

sub set_local_user_used ( $self, $username, $num ) {
    $self->{'local'}{$username}{'used'} = $num // _fail_undef();

    return $self;
}

sub set_local_user_limit ( $self, $username, $num ) {
    $self->{'local'}{$username}{'limit'} = $num // _fail_undef();

    return $self;
}

#----------------------------------------------------------------------

=head2 Remote Setters

The following methods all tell an instance of this class about
properties of one of the user’s remote accounts:

=over

=item * I<OBJ>->set_remote_user_used( $ALIAS, $USERNAME, $COUNT )

=item * I<OBJ>->set_remote_user_limit( $ALIAS, $USERNAME, $COUNT )

=back

=cut

sub get_remote_user_used ( $self, $alias, $username ) {
    return $self->{'remote'}{$alias}{$username}{'used'} // _fail_undef();
}

sub get_remote_user_limit ( $self, $alias, $username ) {
    return $self->{'remote'}{$alias}{$username}{'limit'} // _fail_undef();
}

sub set_remote_user_used ( $self, $alias, $username, $num ) {
    $self->{'remote'}{$alias}{$username}{'used'} = $num // _fail_undef();

    return $self;
}

sub set_remote_user_limit ( $self, $alias, $username, $num ) {
    $self->{'remote'}{$alias}{$username}{'limit'} = $num // _fail_undef();

    return $self;
}

#----------------------------------------------------------------------

sub _fail_undef() {

    # This should not happen. If it does we want to know as much
    # as we can about how we got here, so a stack trace is appropriate.
    Carp::confess 'undef is an invalid value';
}

1;
