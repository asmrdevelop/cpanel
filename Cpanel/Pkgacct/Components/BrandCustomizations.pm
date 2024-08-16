package Cpanel::Pkgacct::Components::BrandCustomizations;

# cpanel - Cpanel/Pkgacct/Components/BrandCustomizations.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Pkgacct::Components::BrandCustomizations

=head1 SYNOPSIS

    my $obj = Cpanel::Pkgacct->new( ... );
    $obj->perform_component('BrandCustomizations');

=head1 DESCRIPTION

This module exists to be called from L<Cpanel::Pkgacct>. It should not be
invoked directly except from that module.

It backs up the user’s customizations for cpanel themes.

=head1 METHODS

=cut

use strict;
use warnings;

use parent 'Cpanel::Pkgacct::Component';

use Cpanel::FileUtils::Dir   ();
use Cpanel::SimpleSync::CORE ();
use Cpanel::Themes::Fallback ();

=head2 I<OBJ>->perform()

This provides a common access point for Components, and should not be called directly under normal circumstances.

=cut

sub perform {
    my ($self)     = @_;
    my $output_obj = $self->get_output_obj();
    my $work_dir   = $self->get_work_dir();
    my $username   = $self->get_user();

    #Seek out and sync any reseller customization files
    my $customization_path = Cpanel::Themes::Fallback::get_global_directory("/resellers/$username");
    my $fs_nodes_ar        = Cpanel::FileUtils::Dir::get_directory_nodes_if_exists($customization_path);
    return 1 if !$fs_nodes_ar;
    my @files = grep { m/\.json$/ } @$fs_nodes_ar;

    foreach my $json_file (@files) {
        my $src_file  = $customization_path . '/' . $json_file;
        my $dest_file = $work_dir . '/customizations/' . $json_file;

        my ( $status, $message ) = Cpanel::SimpleSync::CORE::syncfile( $src_file, $dest_file );
        if ( $status == 0 ) {
            $output_obj->warn("Failed to sync $src_file to $dest_file: $message");
        }
    }
    return 0;
}

1;
