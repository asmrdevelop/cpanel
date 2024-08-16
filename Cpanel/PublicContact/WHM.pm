package Cpanel::PublicContact::WHM;

# cpanel - Cpanel/PublicContact/WHM.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::PublicContact::WHM

=head1 SYNOPSIS

    my $pc_user = Cpanel::PublicContact::WHM::get_pc_user();

=head1 DESCRIPTION

This module contains PublicContact logic that’s meant specifically for WHM.

=cut

use Whostmgr::ACLS ();

=head1 FUNCTIONS

=head2 $username = get_pc_user()

Returns the username that the operating user (taken from
C<$ENV{'REMOTE_USER'}>) should use to access PublicContact. For
root-enabled resellers, for example, this will be C<root>.

=cut

sub get_pc_user {
    return Whostmgr::ACLS::hasroot() ? 'root' : $ENV{'REMOTE_USER'};
}

1;
