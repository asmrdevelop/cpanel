
# cpanel - Cpanel/ImagePrep/Check/backups.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ImagePrep::Check::backups;

use cPstrict;
use parent 'Cpanel::ImagePrep::Check';

use Cpanel::Backup::BackupSet        ();
use Cpanel::Backup::MetadataDB::Tiny ();
use Cpanel::Backup::Transport        ();

=head1 NAME

Cpanel::ImagePrep::Check::backups - A subclass of C<Cpanel::ImagePrep::Check>.

=cut

sub _description {
    return <<~"EO_DESC";
        Check for existing backups and backup destinations.
        EO_DESC
}

sub _check ($self) {

    my $backup_sets = Cpanel::Backup::BackupSet::backup_set_list();
    if ( @{$backup_sets} ) {
        die <<~"EO_BACKUPS";
            One or more user backup sets exist. This is not a supported configuration for template VMs.

            Users with backups:
            @{[join "\n", map { "  - $_->{user}" } @{$backup_sets}]}
            EO_BACKUPS
    }
    else {
        $self->loginfo("No user backup sets exist.");
    }

    # Calling base_path() does also create the directory if it does not already exist.
    my $metadata_dir = Cpanel::Backup::MetadataDB::Tiny::base_path();
    if ( $self->common->_glob("$metadata_dir/*") ) {
        die <<~"EO_METADATA";
            One or more files exist in the '$metadata_dir' directory. This is not a supported configuration for template VMs.
            EO_METADATA
    }
    else {
        $self->loginfo("No user backup metadata files exist.");
    }

    my $dest_href = Cpanel::Backup::Transport::get_destinations();
    if ( my @destinations = sort map { $dest_href->{$_}->{name} } keys %{$dest_href} ) {
        die <<~"EO_DEST";
            One or more backup destinations exist. This is not a supported configuration for template VMs.

            Backup Destinations:
            @{[join "\n", map { "  - $_" } @destinations]}
            EO_DEST
    }
    else {
        $self->loginfo('There are no additional backup destinations configured.');
    }

    return;
}

1;
