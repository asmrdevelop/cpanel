package Cpanel::LinkedNode::Index::Read;

# cpanel - Cpanel/LinkedNode/Index/Read.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Index::Read

=head1 DESCRIPTION

See L<Cpanel::LinkedNode::Index> for more information about this
datastore.

=cut

#----------------------------------------------------------------------

use Cpanel::LoadFile          ();
use Cpanel::LinkedNode::Index ();
use Cpanel::JSON              ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $hr = get()

Reads the datastore. The response is a hash reference; each hash entry’s
key is a node’s alias, and the entry’s value is a
L<Cpanel::LinkedNode::Privileged::Configuration> instance for that node.

=cut

sub get() {
    my $path = Cpanel::LinkedNode::Index::file();

    my $resp_hr = Cpanel::LoadFile::load_if_exists($path);

    if ($resp_hr) {
        $resp_hr = Cpanel::JSON::Load($resp_hr);

        Cpanel::LinkedNode::Index::objectify_contents($resp_hr);
    }

    return $resp_hr || {};
}

1;
