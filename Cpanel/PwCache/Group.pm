package Cpanel::PwCache::Group;

# cpanel - Cpanel/PwCache/Group.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadFile ();
use Cpanel::Context  ();

=encoding utf-8

=head1 NAME

Cpanel::PwCache::Group - Tools for supplemental groups

=head1 SYNOPSIS

    use Cpanel::PwCache::Group;

    my @groups = Cpanel::PwCache::Group::getgroups('bob');

    my @sup_gids = Cpanel::PwCache::Group::get_supplemental_gids_for_user('bob');

=head1 WARNING

This module does not validate that the user exists.
It is the responsibity of the caller to do so.

=cut

=head2 getgroups

Get a list of a users supplemental groups

=over 2

=item Input

=over 3

=item C<SCALAR>

    The user to get the groups for.

=back

=item Output

=over 3

=item C<ARRAY>

    A list of named groups

=back

=back

=cut

sub getgroups {
    my ($user) = @_;
    Cpanel::Context::must_be_list();
    my $regex      = qr/^([^\:]+):[^\:]+:[^\:]+:(?:\s*\Q$user\E\s*$|\s*\Q$user\E\s*,|.*,\s*\Q$user\E\s*,|.*,\s*\Q$user\E\s*$)/;
    my $groups_ref = Cpanel::LoadFile::load_r('/etc/group');
    my $code       = 'map { $_ =~ m{$regex}o ? ($1) : () } split( m{\n}, $$groups_ref )';                                         # eval to allow /o on the regex
    return eval $code;                                                                                                            ## no critic qw(BuiltinFunctions::ProhibitStringyEval)
}

=head2 get_supplemental_gids_for_user

Get a list of a users supplemental gids

=over 2

=item Input

=over 3

=item C<SCALAR>

    The user to get the supplemental gids for.

=back

=item Output

=over 3

=item C<ARRAY>

    A list of gids

=back

=back

=cut

sub get_supplemental_gids_for_user {
    my ($user) = @_;
    Cpanel::Context::must_be_list();
    return ( map { $_ eq $user ? () : ( getgrnam($_) )[2] } getgroups($user) );
}

1;
