package Cpanel::TaskProcessors::BackupMetadataConversion;

# cpanel - Cpanel/TaskProcessors/BackupMetadataConversion.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::TaskProcessors::BackupMetadataConversion - Task processor for backup metadata v3.0

=head1 DESCRIPTION

Deferred task migrating from original backup metadata format to v3.0 of the metadata

=head2 Cpanel::TaskProcessors::BackupMetadataConversion::to_register

Used by the L<Cpanel::TaskQueue::PluginManager> to register the included classes.

=head1 TASKS

=over

=item C<backups_create_metadata> - Runs the system-wide conversion script

=back

=cut

{

    package Cpanel::TaskProcessors::BackupMetadataConversionRun;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        # This gets compiled in to queueprocd, so this lookup has to happen at run time inside this sub

        my $migration_script = '/usr/local/cpanel/scripts/backups_create_metadata';
        return unless -x $migration_script;
        return $self->checked_system(
            {
                'logger' => $logger,
                'name'   => 'migrate',
                'cmd'    => $migration_script,
                'args'   => ["--all"]
            }
        );
    }

    sub deferral_tags {
        my ($self) = @_;
        return qw/metadata/;
    }
}

sub to_register {
    return (
        [ 'backups_create_metadata3_backup_dir', Cpanel::TaskProcessors::BackupMetadataConversionRun->new() ],
    );
}

1;
