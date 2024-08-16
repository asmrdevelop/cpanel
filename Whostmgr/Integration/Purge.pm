package Whostmgr::Integration::Purge;

# cpanel - Whostmgr/Integration/Purge.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

=encoding UTF-8

Whostmgr::Integration::Purge

=head1 DESCRIPTION

root level functions related to purging Integration.

=cut

=head1 SYNOPSIS

    use Whostmgr::Integration::Purge;

    Whostmgr::Integration::Purge::purge_user(
        $username,
    );

=cut

=head1 DESCRIPTION

=cut

use strict;
use warnings;

use Cpanel::Integration::Config ();

=head2 purge_user( USER )

=head3 Purpose

Remove all of a cPanel user’s integration data.

=over

=item * USER: string (required) - The user whose data to delete

=back

=cut

sub purge_user {
    my ($user) = @_;

    require File::Path;

    my @dirs = (
        Cpanel::Integration::Config::links_dir_for_user($user),
        Cpanel::Integration::Config::dynamicui_dir_for_user($user),
    );

    !( -d $_ ) || File::Path::remove_tree($_) for @dirs;

    return;
}
1;
