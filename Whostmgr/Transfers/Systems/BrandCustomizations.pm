package Whostmgr::Transfers::Systems::BrandCustomizations;

# cpanel - Whostmgr/Transfers/Systems/BrandCustomizations.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Try::Tiny;

use Cpanel::FileUtils::Dir ();
use Cpanel::JSON           ();
use Cpanel::LoadFile       ();

use parent qw(
  Whostmgr::Transfers::Systems
);

=head1 NAME

Whostmgr::Transfers::Systems::BrandCustomizations - A Transfer Systems module to restore a user's brand customizations.

=head1 SYNOPSIS

    use Whostmgr::Transfers::Systems::BrandCustomizations;
    my $transfer = Whostmgr::Transfers::Systems::BrandCustomizations->new();
    $transfer->unrestricted_restore();

=head1 DESCRIPTION

This module implements a C<Whostmgr::Transfers::Systems> module. It is responsible for restoring the
brand customizations, if any, for a given user.

=head1 METHODS

=cut

=head2 get_phase()

Override the default phase for a C<Whostmgr::Transfers::Systems> module.

=cut

sub get_phase {
    return 25;
}

=head2 get_summary()

Provide a summary of what this module is supposed to do.

=cut

sub get_summary {
    my ($self) = @_;
    return ['This restores user-level brand customizations.'];
}

=head2 get_restricted_available()

Mark this module as available for retricted restores.

=cut

sub get_restricted_available {
    return 1;
}

=head2 get_notes()

Provide slightly more extensive information on what this module is supposed to do.

=cut

sub get_notes {
    my ($self) = @_;
    return ['This restores all brand customization data associated with an account.'];
}

=head2 unrestricted_restore()

The function that does the work of restoring brand customizations for a user.

This method is also aliased to C<restricted_restore>.

B<Returns>: C<1>

=cut

sub unrestricted_restore {
    my ($self) = @_;
    my $extractdir = $self->extractdir();
    $self->start_action("Restoring customization data");

    my $source_dir = "$extractdir/customizations";
    for my $item ( $self->_fetch_customization_files($source_dir) ) {
        $self->_validate_and_write_customization( $source_dir, $item );
    }
    return 1;
}

*restricted_restore = \&unrestricted_restore;

sub _fetch_customization_files {
    my ( $self, $source_dir ) = @_;
    my @list;

    if ( !-e $source_dir ) { return; }

    my $nodes = Cpanel::FileUtils::Dir::get_directory_nodes_if_exists($source_dir);
    if ($nodes) {
        @list = grep { m/\.json$/ } @$nodes;
    }
    else {
        $self->warn("Unable to open $source_dir");
    }
    return @list;
}

sub _validate_and_write_customization {
    my ( $self, $dir, $file ) = @_;
    my $user = $self->newuser();
    require Whostmgr::Customizations;

    #Use the base filename to parse an app and theme from it.
    #If anything goes wrong, let the Customizations module handle it.
    my ($base) = split /\./, $file;
    my ( $app, $theme ) = split /_/, $base;

    #Get customization data from the file
    my $brand;
    my $json = Cpanel::LoadFile::load_if_exists("$dir/$file");
    if ($json) {
        my $data = eval { Cpanel::JSON::Load($json) };
        if ( !$data ) {
            $self->warn("Unable to parse the json found in $file.");
            return;
        }
        $brand = $data->{"default"};    #We need this specific entry
    }
    if ( !$brand ) {
        $self->warn("Failed to read brand data from $file");
        return;
    }

    try {
        my $add_result = Whostmgr::Customizations::add( $user, $app, $theme, $brand );
        if ( $add_result->{'Validated'} ) {

            #We're not concerned about any warnings they get, only that it validated
            $self->out("Restoring customization data for $file");
        }
        else {
            #Validation failed.  Log why.
            foreach my $error ( @{ $add_result->{'errors'} } ) { $self->warn("Invalid Customization data in $file: $error"); }
        }
    }
    catch {
        $self->warn("General failure adding Customization data from $file: $_");
    };

    return;
}

1;
