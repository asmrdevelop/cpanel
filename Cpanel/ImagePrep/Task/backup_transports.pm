
# cpanel - Cpanel/ImagePrep/Task/backup_transports.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ImagePrep::Task::backup_transports;

use cPstrict;

use parent 'Cpanel::ImagePrep::Task';
use Cpanel::Imports;
use Cpanel::Autodie               ();
use Cpanel::Backup::Transport::DB ();

=head1 NAME

Cpanel::ImagePrep::Task::backup_transports - An implementation subclass of Cpanel::ImagePrep::Task. See parent class for interface.

=cut

sub _description {
    return <<EOF;
If /backup/transports.db (or transports.db at an alternate location) exists, delete it.
Even if a backup transport has not been added, the file can get created when visiting
the backup configuration section of WHM. This file can contain sensitive data that
would not be adequately cleansed simply by deleting (backup transport credentials), but
in this case it would be detected by the 'backup' check.
EOF
}

sub _type { return 'non-repair only' }

sub _pre {
    my ($self) = @_;
    my ( $ok, $file ) = Cpanel::Backup::Transport::DB->remove();
    if ( !$ok ) {
        die "Failed to delete $file\n";
    }
    $self->loginfo("Deleted $file");
    return $self->PRE_POST_OK;
}

sub _post {
    return shift->PRE_POST_NOT_APPLICABLE;
}

1;
