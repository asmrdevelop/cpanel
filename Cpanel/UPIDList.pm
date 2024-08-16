package Cpanel::UPIDList;

# cpanel - Cpanel/UPIDList.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::UPIDList - Manage a list of UPIDs

=head1 SYNOPSIS

    my $list = Cpanel::UPIDList->new( $serialized_list_of_upids );

    $list->prune();

    my @status_quo = $list->get();

    $list->add_current_process();

    my $new_serialized_list_str = $list->serialize();

=head1 DESCRIPTION

This class encapsulates useful logic for tracking a list of processes by their
UPIDs. (See L<Cpanel::UPID> for more information about UPIDs.)

=cut

use Cpanel::Context ();
use Cpanel::UPID    ();

=head1 METHODS

=head2 I<CLASS>->new( $SERIALIZED_LIST )

Instantiates this class. $SERIALIZED_LIST is optional.

=cut

sub new {
    my ( $class, $str ) = @_;

    my @split = split m<,>, ( $str // q<> );

    return bless \@split, $class;
}

=head2 @upids = I<OBJ>->get()

Returns the contents of the object as a list of UPIDs.

=cut

sub get {
    my ($self) = @_;

    Cpanel::Context::must_be_list();

    return @$self;
}

=head2 $str = I<OBJ>->serialize()

Returns the contents of the object as a string suitable for
use in files. The format is undefined. I<OBJ> is returned.

=cut

sub serialize {
    my ($self) = @_;

    return join q<,>, @$self;
}

=head2 I<OBJ>->add( $PID )

This adds the process referred to by $PID to the object, if $PID is
still active.

If $PID is not an active process, undef is returned; otherwise,
$PID’s UPID is returned.

=cut

sub add {
    my ( $self, $pid ) = @_;

    my $upid = Cpanel::UPID::get($pid);

    push @$self, $upid if $upid;

    return $upid;
}

=head2 I<OBJ>->prune();

This removes any processes that are no longer active from the object.
I<OBJ> is returned.

=cut

sub prune {
    my ($self) = @_;

    @$self = grep { Cpanel::UPID::is_alive($_) } @$self;

    return $self;
}

1;
