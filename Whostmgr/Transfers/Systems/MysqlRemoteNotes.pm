package Whostmgr::Transfers::Systems::MysqlRemoteNotes;

# cpanel - Whostmgr/Transfers/Systems/MysqlRemoteNotes.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::JSON                 ();
use Cpanel::Mysql::Remote::Notes ();

use parent 'Whostmgr::Transfers::Systems';

=head1 NAME

Whostmgr::Transfers::Systems::MysqlRemoteNotes - A Transfer Systems module to restore a user's MySQL Remote notes

=head1 SYNOPSIS

    use Whostmgr::Transfers::Systems::MysqlRemoteNotes;

    my $transfer = Whostmgr::Transfers::Systems::MysqlRemoteNotes->new(
         utils => $whostmgr_transfers_utils_obj,
         archive_manager => $whostmgr_transfers_archivemanager_obj,
    );
    $transfer->unrestricted_restore();

=head1 DESCRIPTION

This module implements a C<Whostmgr::Transfers::Systems> module. It is
responsible for restoring the MySQL Remote notes for a given user.

=head1 METHODS

=cut

=head2 get_phase()

Override the default phase for a C<Whostmgr::Transfers::Systems> module.

=cut

sub get_phase ($self) {
    return 40;
}

=head2 get_summary()

Provide a summary of what this module is supposed to do.

=cut

sub get_summary ($self) {
    return [ $self->_locale()->maketext('The [asis,MysqlRemoteNotes] module restores the Remote [asis,MySQL] comments for an account.') ];
}

=head2 get_restricted_available()

Mark this module as available for retricted restores.

=cut

sub get_restricted_available ($self) {
    return 1;
}

=head2 unrestricted_restore()

The function that actually does the work of restoring the notes file for
a user. It will only restore a notes file if it exists in the packages.
This method is also aliased to C<restricted_restore>.

B<Returns>: C<1>

=cut

sub unrestricted_restore ($self) {
    my $extractdir = $self->{'_archive_manager'}->trusted_archive_contents_dir();

    my $archive_notes_file = "$extractdir/mysql_host_notes.json";

    return 1 if ( !-f $archive_notes_file || -z $archive_notes_file );

    my $newuser = $self->{'_utils'}->local_username();

    $self->start_action('Restoring Remote MySQL comments');

    my $stored_hr = Cpanel::JSON::LoadFile($archive_notes_file);

    # initialize the notes for the user, in case the directories do not exist
    my $notes_obj = Cpanel::Mysql::Remote::Notes->new( username => $newuser );

    $notes_obj->set(%$stored_hr);

    return 1;
}

*restricted_restore = \&unrestricted_restore;

1;
