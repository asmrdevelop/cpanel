package Cpanel::XTables::Whitelist;

# cpanel - Cpanel/XTables/Whitelist.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent 'Cpanel::XTables';

=head1 NAME

Cpanel::XTables::Whitelist

=head1 SYNOPSIS

    use Cpanel::XTables::Whitelist();

    my $obj = Cpanel::XTables::Whitelist->new( 'chain' => 'someChain' );
    $obj->accept_in_both_directions('1.2.3.4');

=head1 DESCRIPTION

This modules is both a *factory*, *submodule* and a *base class* for abstracting
away the differences between IPTables and NFTables so that interfaces which
rely on IP/NFTables don't have to maintain separate logic for whitelisting.

Whichever subclass is the appropriate one to load for your OS Version will
be the object returned by the constructor:
CentOS 7 or below: Cpanel::IPTables::Whitelist object
CentOS 8: Cpanel::NFTables::Whitelist object

=head2 SEE ALSO

Cpanel::IpTables::Whitelist
Cpanel::NFTables::Whitelist

=head1 METHODS

=head2 accept_in_both_directions

Implemented in subclasses.

=cut

sub accept_in_both_directions {
    die "accept_in_both_directions only implemented in subclass!";
}

1;
