package Whostmgr::Transfers::Systems::BackupConfig;

# cpanel - Whostmgr/Transfers/Systems/BackupConfig.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# RR Audit: JNK

use base qw(
  Whostmgr::Transfers::Systems
);

use Cpanel::Backup::Config ();
use Cpanel::Config::Backup ();    # PPI USE OK - view backup_systems

sub get_prereq {
    return ['CpUser'];
}

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This installs the backup configuration based on the target system’s defaults.') ];
}

sub get_restricted_available {
    return 1;
}

my @backup_systems = (
    {
        'config_module' => 'Cpanel::Backup::Config',
        'legacy'        => 0,

    },
    {
        'config_module' => 'Cpanel::Config::Backup',
        'legacy'        => 1,
    }
);

sub unrestricted_restore {
    my ($self) = @_;

    my $newuser = $self->{'_utils'}->local_username();

    foreach my $backup_system (@backup_systems) {
        my $config_module     = $backup_system->{'config_module'};
        my $backup_config_ref = "$config_module"->load();

        # When restoring an account, if they were previously selected to be included in backups,
        # we assume the same will be true on the "new" server.
        # If they were specifically disabled from backups, we'll assume the same as well.
        # Otherwise we'll enable them for backups if backups are enabled on the server.
        my $force_state = 0;
        if ( defined( $self->{'_utils'}{'_cpuser_data'}[0]{'BACKUP'} ) && $self->{'_utils'}{'_cpuser_data'}[0]{'BACKUP'} == 1 ) {
            $force_state = 1;
        }
        elsif ( defined( $self->{'_utils'}{'_cpuser_data'}[0]{'BACKUP'} ) && $self->{'_utils'}{'_cpuser_data'}[0]{'BACKUP'} == 0 ) {
            $force_state = 0;
        }
        else {
            if ( $backup_config_ref->{'BACKUPENABLE'} eq 'yes' and $backup_config_ref->{'BACKUPACCTS'} eq 'yes' ) {
                $force_state = 1;
            }
        }

        $self->start_action( $backup_system->{'legacy'} ? $self->_locale()->maketext("Restoring legacy backup config …") : $self->_locale()->maketext("Restoring backup config …") );

        # Update "new" backup config for the account
        my ( $ret, $msg ) = Cpanel::Backup::Config::toggle_user_backup_state(
            {
                'user'   => $newuser,
                'legacy' => $backup_system->{'legacy'},
                'BACKUP' => $force_state
            }
        );

        if ( !$ret ) {
            $self->warn(
                  $backup_system->{'legacy'}
                ? $self->_locale()->maketext( "Could not update legacy backup config for “[_1]”: [_2]", $newuser, $msg )
                : $self->_locale()->maketext( "Could not update backup config for “[_1]”: [_2]",        $newuser, $msg )
            );
        }
        else {
            $self->out(
                  $backup_system->{'legacy'}
                ? $self->_locale()->maketext( "Updated legacy backup config for “[_1]”.", $newuser )
                : $self->_locale()->maketext( "Updated backup config for “[_1]”.",        $newuser )
            );
        }
    }

    return 1;
}

*restricted_restore = \&unrestricted_restore;

1;
