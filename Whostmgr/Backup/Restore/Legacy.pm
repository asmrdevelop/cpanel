package Whostmgr::Backup::Restore::Legacy;

# cpanel - Whostmgr/Backup/Restore/Legacy.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# This module restores backups created with the “Legacy Backup System”

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings) -- cpanel.pl is not yet warnings safe

use Whostmgr::Transfers::Session::Preflight::Restore ();
use Cpanel::Validate::FilesystemNodeName             ();
use Whostmgr::Transfers::Session::Setup              ();
use Whostmgr::Transfers::Session::Constants          ();
use Whostmgr::Transfers::Session::Config             ();
use Cpanel::AcctUtils::Account                       ();
use Cpanel::Autodie                                  ();
use Cpanel::BackupMount                              ();
use Cpanel::BackupMount::Object                      ();
use Cpanel::Hostname                                 ();
use Cpanel::Exception                                ();
use Cpanel::Context                                  ();
use Cpanel::Config::Backup                           ();
use Try::Tiny;

###########################################################################
#
# Method:
#   enqueue_restore_backup
#
# Description:
#   Create a transfer session and enqueue a legacy
#   backup to be restored.
#
# Parameters:
#   user - The user to restore the backup for
#   restoretype -  The legacy backup type
#       Allowed Values: daily, weekly, monthly
#   db_restore_method - The method to use to choose
#           which databases from the backup should be restored.
#       Allowed Values: select, overwrite_all, overwrite_sameowner
#       Note: If 'select' is the value the following options
#           must be passed to 'select' which databases to restore:
#               mysql_dbs_to_restore
#               pgsql_dbs_to_restore
#   dbuser_restore_method -  The method to use to choose
#           which database users from the backup should be restored
#       Allowed Values: overwrite_all, overwrite_sameowner
#   mysql_dbs_to_restore - An array ref of MySQL databases that should
#        be restored from the backup (this will overwrite any same name dbs).
#        For this option to be observed, db_restore_method must be
#        set to 'select'
#   pgsql_dbs_to_restore - An array ref of PostgreSQL databases that should
#        be restored from the backup (this will overwrite any same name dbs).
#        For this option to be observed, db_restore_method must be
#        set to 'select'
#   restoreip -  Determines if the account should be restored with a
#                dedicated ip
#       Allowed Values: 0,1
#   restoremail -  Determines email should be restored from the backup
#       Allowed Values: 0,1
#   restoremysql -  Determines if mysql assets should be restored from the backup
#       Allowed Values: 0,1
#   restoremysql -  Determines if postgres assets should be restored from the backup
#       Allowed Values: 0,1
#   restorebwdata -  Determines if bandwidth data should be restored from the backup
#       Allowed Values: 0,1
#   restoresubs -  Determines if the subdomains should be restored from the backup
#       Allowed Values: 0,1
#
# Exceptions:
#   None.  Arguments are trapped into a two part return
#
# Returns:
#   Two Part
#       ( 1, The transfers session id that has the backup restore enqueued )
#          or
#       ( 0,  An error )
#
sub enqueue_restore_backup {
    my (%opts) = @_;

    Cpanel::Context::must_be_list();
    my $host = Cpanel::Hostname::gethostname();
    my $err;
    try {
        foreach my $required (qw(user restoretype)) {
            if ( !length $opts{$required} ) {
                die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $required ] );
            }
        }

        # Verify the backup exists so we can fail before
        # we setup the restore session in order to preserve
        # legacy behavior.
        get_user_backup_info_for_restore_type( $opts{'user'}, $opts{'restoretype'} );
    }
    catch {
        $err = $_;
    };

    if ($err) {
        return ( 0, Cpanel::Exception::get_string($err) );
    }

    my ( $adjust_ok, $adjust_msg ) = Whostmgr::Transfers::Session::Preflight::Restore::ensure_mysql_is_sane_for_restore();
    if ( !$adjust_ok ) {
        return ( $adjust_ok, $adjust_msg );
    }

    my ( $setup_ok, $session_obj ) = Whostmgr::Transfers::Session::Setup::setup_session_obj(
        {
            'initiator'           => 'legacybackuprestore',
            'create'              => 1,
            'session_id_template' => $host,
        },
        {
            'session' => {
                'scriptdir'    => '/scripts',
                'state'        => 'preflight',
                'session_type' => $Whostmgr::Transfers::Session::Constants::SESSION_TYPES{'Legacy'},
            },
            'queue'   => { 'RESTORE' => 0 },
            'options' => {
                'unrestricted' => $Whostmgr::Transfers::Session::Config::UNRESTRICTED,
            },
        }
    );

    if ( !$setup_ok ) {
        return ( $setup_ok, $session_obj );
    }

    $session_obj->set_source_host('localhost');

    my $id = $session_obj->id();

    my $db_restore_method     = $opts{'db_restore_method'};
    my $dbuser_restore_method = $opts{'dbuser_restore_method'};
    my $user                  = $opts{'user'};
    my $restoretype           = $opts{'restoretype'};

    my %restore_options = (
        'user'                        => $user,
        'restoretype'                 => $restoretype,
        'restoreall'                  => ( Cpanel::AcctUtils::Account::accountexists($user) ? 0 : 1 ),
        'restoreip'                   => ( $opts{'restoreip'}                               ? 1 : 0 ),
        'restoremail'                 => ( $opts{'restoremail'}                             ? 1 : 0 ),
        'restoremysql'                => ( $opts{'restoremysql'}                            ? 1 : 0 ),
        'restorepsql'                 => ( $opts{'restorepsql'}                             ? 1 : 0 ),
        'restorebwdata'               => ( $opts{'restorebwdata'}                           ? 1 : 0 ),
        'restoresubs'                 => ( $opts{'restoresubs'}                             ? 1 : 0 ),
        'unrestricted_restore'        => 1,    # Currently backup restores are always unrestricted
        'overwrite_all_dbs'           => 0,
        'overwrite_sameowner_dbs'     => 0,
        'overwrite_sameowner_dbusers' => 0,
        'overwrite_all_dbusers'       => 0,
    );

    if ( $db_restore_method eq 'select' ) {
        $restore_options{'mysql_dbs_to_restore'} = join( ',', @{ $opts{'mysql_dbs_to_restore'} } );
        $restore_options{'pgsql_dbs_to_restore'} = join( ',', @{ $opts{'pgsql_dbs_to_restore'} } );
    }
    elsif ( $db_restore_method eq 'overwrite_all' ) {
        $restore_options{'overwrite_all_dbs'} = 1;
    }
    else {
        $restore_options{'overwrite_sameowner_dbs'} = 1;
    }

    if ( $dbuser_restore_method eq 'overwrite_all' ) {
        $restore_options{'overwrite_all_dbusers'} = 1;
    }
    else {
        $restore_options{'overwrite_sameowner_dbusers'} = 1;
    }

    my $enqueue_error;
    try {
        $session_obj->enqueue( 'LegacyAccountBackup', \%restore_options, $Whostmgr::Transfers::Session::Constants::QUEUE_STATES{'RESTORE_PENDING'} );
    }
    catch {
        $enqueue_error = $_;
    };

    if ($enqueue_error) {
        $session_obj->disconnect();    # TP TASK 20767 disconnect before global destruct
        return ( 0, Cpanel::Exception::get_string($enqueue_error) );
    }

    $session_obj->disconnect();        # TP TASK 20767 disconnect before global destruct
    return ( 1, $id );

}

#
#$restoretype is 'daily', 'weekly', or 'monthly'.
#
#This returns a hashref:
#   {
#       source_dir              - the directory where the backup node is
#
#       source_file             - the name of the backup node
#                                 (If this is an incremental backup, then
#                                 'source_file' is a dir; otherwise, a file.)
#
#       source_is_incremental   - whether it's an incremental backup (1 or 0)
#
#       backup_mount_object     - a reference to a Cpanel::BackupMount::Object
#                                 instance that, when DESTROYed, will
#                                 unmount the backup partition. If the backup
#                                 disk was already mounted, then this is undef.
#   }
#

sub get_user_backup_info_for_restore_type {
    my ( $user, $restoretype ) = @_;

    Cpanel::Validate::FilesystemNodeName::validate_or_die($user);
    Cpanel::Validate::FilesystemNodeName::validate_or_die($restoretype);

    my $backup_conf = Cpanel::Config::Backup::load();
    my $backup_mount;

    if ( $backup_conf && $backup_conf->{'BACKUPMOUNT'} && $backup_conf->{'BACKUPMOUNT'} eq 'yes' ) {

        # need to unmount disk only if it was not previously mounted
        if ( !Cpanel::BackupMount::backup_disk_is_mounted( $backup_conf->{'BACKUPDIR'} ) ) {
            $backup_mount = Cpanel::BackupMount::Object->new(
                mount_point => $backup_conf->{'BACKUPDIR'},
                ttl         => 15000,
            );
        }
    }
    my $source_dir = $backup_conf->{'BACKUPDIR'} . '/cpbackup/' . $restoretype;

    my %source_dest = (
        "$source_dir/$user.tar.bz2" => "$user.tar.bz2",    # compressed bz2
        "$source_dir/$user.tar.gz"  => "$user.tar.gz",     # compressed gz
        "$source_dir/$user.tgz"     => "$user.tgz",        # compressed gz
        "$source_dir/$user.tar"     => "$user.tar",        # uncompressed
        "$source_dir/$user/cp"      => $user,              # incremental
    );
    for my $source_path ( keys %source_dest ) {
        if ( Cpanel::Autodie::exists($source_path) ) {
            return {
                'source_dir'  => $source_dir,
                'source_file' => $source_dest{$source_path},

                #This is special: whenever the last reference to this object goes away,
                #the backup mount will go away (via DESTROY).
                'backup_mount_object' => $backup_mount,
            };
        }
    }

    die Cpanel::Exception->create( "The directory “[_1]” does not contain a backup for the user “[_2]”.", [ $source_dir, $user ] );
}

1;
