package Cpanel::XTables::TempBan;

# cpanel - Cpanel/XTables/TempBan.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent 'Cpanel::XTables';

=head1 NAME

Cpanel::XTables::TempBan

=head1 SYNOPSIS

    use Cpanel::XTables::TempBan();

    my $obj = Cpanel::XTables::TempBan->new( 'chain' => 'someChain' );
    my $rules = $obj->add_temp_block('1.2.3.4');

=head1 DESCRIPTION

This module is both a *factory*, *subclass* and a *base class* for abstracting
away the differences between IPTables and NFTables so that interfaces which
rely on IP/NFTables don't have to maintain separate logic for Hulk bans.

Whichever subclass is the appropriate one to load for your OS Version will
be the object returned by the constructor:
CentOS 7 or below: Cpanel::IPTables::TempBan object
CentOS 8: Cpanel::NFTables::TempBan object

=head2 SEE ALSO

Cpanel::IpTables::TempBan
Cpanel::NFTables::TempBan

=head1 METHODS

=head2 add_temp_block

Implemented in subclasses.

=cut

sub add_temp_block {
    die "add_temp_block only implemented in subclasses!";
}

=head2 can_temp_ban

Implemented in subclasses.

=cut

sub can_temp_ban {
    die "can_temp_ban only implemented in subclasses!";
}

=head2 check_chain_position

Implemented in subclasses.

=cut

sub check_chain_position {
    die "check_chain_position only implemented in subclasses!";
}

1;
