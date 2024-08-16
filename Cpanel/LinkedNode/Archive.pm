package Cpanel::LinkedNode::Archive;

# cpanel - Cpanel/LinkedNode/Archive.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Archive

=head1 DESCRIPTION

This module contains logic for the interaction between linked nodes
and account archives.

=cut

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $path = subarchive_relative_root( $WORKER_ALIAS )

Returns the relative path (no leading C</>) of the subarchive root
for a given $WORKER_ALIAS.

=cut

sub subarchive_relative_root ($worker_alias) {
    return "worker_pkgacct/$worker_alias";
}

1;
