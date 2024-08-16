package Cpanel::LinkedNode::Index;

# cpanel - Cpanel/LinkedNode/Index.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Index

=head1 SYNOPSIS

    my $dir = Cpanel::LinkedNode::Index::dir();
    my $file = Cpanel::LinkedNode::Index::file();

    Cpanel::LinkedNode::Index::objectify_contents( \%raw_contents )

=head1 DESCRIPTION

B<IMPORTANT:> This module is meant to be internal to its own namespace.

This module contains groundwork logic for the master linked nodes
datastore. This datastore is authoritative for all linked nodes registered
with the local server.

=cut

#----------------------------------------------------------------------

use Cpanel::LinkedNode::Privileged::Configuration ();

# exposed for testing
our $_DIR = '/var/cpanel/linked_nodes';

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $dir = dir()

Returns the directory that contains C<file()>.

=cut

sub dir {
    return $_DIR;
}

=head2 $dir = file()

Returns the path of the datastore’s file.

=cut

sub file {
    return "$_DIR/master.json";
}

=head2 objectify_contents( \%RAW )

Converts the values of %RAW into
L<Cpanel::LinkedNode::Privileged::Configuration> instances.

=cut

sub objectify_contents ($raw_hr) {
    for my $alias ( keys %$raw_hr ) {
        $raw_hr->{$alias} = Cpanel::LinkedNode::Privileged::Configuration->new( alias => $alias, %{ $raw_hr->{$alias} } );
    }

    return;
}

1;
