package Whostmgr::Transfers::Utils::WorkerNodesObj;

# cpanel - Whostmgr/Transfers/Utils/WorkerNodesObj.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::Utils::WorkerNodesObj

=head1 SYNOPSIS

    my $wn_obj = Whostmgr::Transfers::Utils::WorkerNodesObj->new('/extract/dir');

    my @mail_ipv4s = $wn_obj->get_type_ipv4_addresses('Mail');
    my @mail_ipv6s = $wn_obj->get_type_ipv6_addresses('Mail');

=head1 DESCRIPTION

This module provides an object wrapper around the worker-nodes datastore
from an account archive.

=cut

#----------------------------------------------------------------------

use Cpanel::Context  ();
use Cpanel::LoadFile ();
use Cpanel::JSON     ();

my $FILENAME = 'worker_nodes.json';

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new( $EXTRACTDIR )

Instantiates the class based on the contents of $EXTRACTDIR.

=cut

sub new ( $class, $extractdir ) {
    my $file = "$extractdir/$FILENAME";

    my $worker_conf = Cpanel::LoadFile::load_if_exists($file);

    if ($worker_conf) {
        local $@;

        $worker_conf = eval { Cpanel::JSON::Load($worker_conf) };

        if ( !$worker_conf ) {
            warn "Failed to decode JSON in $FILENAME; ignoring file contents. Error was: $@";
        }
    }

    return bless( $worker_conf || {}, $class );
}

=head2 @types = I<OBJ>->get_worker_types()

Returns the type (e.g., C<Mail>) of each stored worker node.

Must be called in list context.

=cut

sub get_worker_types ($self) {
    Cpanel::Context::must_be_list();

    return keys %$self;
}

=head2 $alias = I<OBJ>->get_type_alias( $TYPE )

Returns the alias of the stored worker node of type $TYPE.
If no such worker node is stored, undef is returned.

=cut

sub get_type_alias ( $self, $type ) {
    return $self->{$type} && $self->{$type}{'alias'};
}

=head2 $hostname = I<OBJ>->get_type_hostname( $TYPE )

Like C<get_type_alias()> but returns the hostname instead.

=cut

sub get_type_hostname ( $self, $type ) {
    return $self->{$type} && $self->{$type}{'hostname'};
}

=head2 @addresses = I<OBJ>->get_type_ipv4_addresses( $TYPE )

Returns the stored IPv4 address(es), if any, of the stored worker
node of type $TYPE (e.g., C<Mail>). Addresses are returned in
standard dotted-quad notation.

Must be called in list context.

=cut

sub get_type_ipv4_addresses ( $self, $type ) {
    return $self->_get_list( $type, 'ipv4' );
}

=head2 @addresses = I<OBJ>->get_type_ipv6_addresses( $TYPE )

Like C<get_type_ipv4_addresses()> but for IPv6 addresses.

Note that the returned addresses may currently appear in any valid
IPv6 text format (e.g., compressed, expanded, …).

=cut

sub get_type_ipv6_addresses ( $self, $type ) {
    return $self->_get_list( $type, 'ipv6' );
}

#----------------------------------------------------------------------

sub _get_list ( $self, $type, $list_name ) {
    Cpanel::Context::must_be_list();

    my @ret;

    if ( $self->{$type} && $self->{$type}{$list_name} ) {
        @ret = @{ $self->{$type}{$list_name} };
    }

    return @ret;
}

1;
