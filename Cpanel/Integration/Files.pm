package Cpanel::Integration::Files;

# cpanel - Cpanel/Integration/Files.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::FileUtils::Dir      ();
use Cpanel::Integration::Config ();

=head1 NAME

Cpanel::Integration::Files

=head1 DESCRIPTION

Load admin and user integration configuration for an application

=cut

=head1 SYNOPSIS

    use Cpanel::Integration::Files ();

    my @files = Cpanel::Integration::Files::get_dynamicui_files_for_user('bob');

=cut

=head2 get_dynamicui_files_for_user( USER )

=head3 Purpose

Get a list of filesystem paths that contain integration DynamicUI files
for the given user.

=head3 Arguments

=over

=item USER: string - The cPanel user who has the app(s) installed

=back

=head3 Returns

=over

=item A list of the filesystem paths. Order is not defined.

=back

=cut

sub get_dynamicui_files_for_user {
    my ($user) = @_;

    my $dynamicui_integration_dir = Cpanel::Integration::Config::dynamicui_dir_for_user($user);

    my $nodes_ar = Cpanel::FileUtils::Dir::get_directory_nodes_if_exists($dynamicui_integration_dir);

    if ( !$nodes_ar ) { return (); }

    return map { index( $_, 'dynamicui_' ) == 0 ? "$dynamicui_integration_dir/$_" : () } @$nodes_ar;
}

1;
