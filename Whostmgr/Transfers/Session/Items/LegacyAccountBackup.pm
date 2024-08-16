package Whostmgr::Transfers::Session::Items::LegacyAccountBackup;

# cpanel - Whostmgr/Transfers/Session/Items/LegacyAccountBackup.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use base qw(Whostmgr::Transfers::Session::Item
  Whostmgr::Transfers::Session::Items::AccountRestoreBase
  Whostmgr::Transfers::Session::Items::Schema::LegacyAccountBackup
);

our $VERSION = '1.1';

use Whostmgr::Backup::Restore            ();
use Whostmgr::Backup::Restore::Legacy    ();
use Whostmgr::Transfers::Session::Config ();

sub module_info {
    my ($self) = @_;

    return { 'item_name' => $self->_locale()->maketext('Account') };
}

sub restore {
    my ($self) = @_;

    return $self->exec_path(
        [
            qw(_restore_init
              _display_options
              _validate_restore_package_input
              check_restore_disk_space
              _restore_package
            ),
            ( $self->can('post_restore') ? 'post_restore' : () )
        ]
    );
}

sub _validate_restore_package_input {
    my ($self) = @_;

    return $self->validate_input( [ 'backup_user', [ 'input', [ 'restorebwdata', 'restoremysql', 'restoresubs', 'restoreall', 'restoremail' ] ] ] );
}

sub _restore_package {
    my ($self) = @_;

    my %restore_args = (
        'user'        => $self->{'backup_user'},
        'restoretype' => $self->{'input'}->{'restoretype'},
        'output_obj'  => $self->{'output_obj'},
        (
            $self->{'input'}->{'pgsql_dbs_to_restore'}
            ? (
                'pgsql_dbs_to_restore' => [ split( m{,}, $self->{'input'}->{'pgsql_dbs_to_restore'} ) ],
              )
            : ()
        ),
        (
            $self->{'input'}->{'mysql_dbs_to_restore'}
            ? (
                'mysql_dbs_to_restore' => [ split( m{,}, $self->{'input'}->{'mysql_dbs_to_restore'} ) ],
              )
            : ()
        ),
        'overwrite_all_dbs'           => ( $self->{'input'}->{'overwrite_all_dbs'}           ? 1 : 0 ),
        'overwrite_all_dbusers'       => ( $self->{'input'}->{'overwrite_all_dbusers'}       ? 1 : 0 ),
        'overwrite_sameowner_dbs'     => ( $self->{'input'}->{'overwrite_sameowner_dbs'}     ? 1 : 0 ),
        'overwrite_sameowner_dbusers' => ( $self->{'input'}->{'overwrite_sameowner_dbusers'} ? 1 : 0 ),
        'restorereseller'             => 1,
        'restorebwdata'               => ( $self->{'input'}->{'restorebwdata'} ? 1 : 0 ),
        'restoremysql'                => ( $self->{'input'}->{'restoremysql'}  ? 1 : 0 ),
        'restorepsql'                 => ( $self->{'input'}->{'restorepsql'}   ? 1 : 0 ),
        'restoreparked'               => 1,
        'restoreip'                   => ( $self->{'input'}->{'restoreip'}   ? 1 : 0 ),
        'restoresubs'                 => ( $self->{'input'}->{'restoresubs'} ? 1 : 0 ),
        'restoreall'                  => ( $self->{'input'}->{'restoreall'}  ? 1 : 0 ),
        'restoremail'                 => ( $self->{'input'}->{'restoremail'} ? 1 : 0 ),
        'unrestricted_restore'        => $Whostmgr::Transfers::Session::Config::UNRESTRICTED,
        'percentage_coderef'          => sub {
            my ($pct) = @_;
            my $relative_pct = int( 10 + ( $pct * .8 ) );

            $self->set_percentage($relative_pct);
        }
    );

    my ( $restore_status, $restore_message );

    ( $restore_status, $restore_message, $self->{'account_restore_obj'} ) = Whostmgr::Backup::Restore::restore_account(%restore_args);

    return ( $restore_status, $restore_status ? $restore_message : $self->_locale()->maketext( "Account Restore Failed: “[_1]”", $restore_message ) );
}

sub _display_options {
    my ($self) = @_;
    $self->set_percentage(10);
    print $self->_locale()->maketext('Restore Reseller Privileges: yes') . "\n";
    print $self->_locale()->maketext('Restricted mode: no') . "\n";
    print $self->_locale()->maketext( 'Backup User: “[_1]”', $self->{'backup_user'} ) . "\n";
    return ( 1, 'OK' );
}

sub _restore_init {
    my ($self) = @_;

    $self->session_obj_init();

    $self->{'backup_user'} = $self->{'input'}->{'user'} || $self->item();    # self->item() FKA $self->{'input'}->{'user'};

    return $self->validate_input( [qw(session_obj options session_info output_obj backup_user)] );
}

sub is_transfer_item {
    return 0;
}

sub get_restore_source_path {
    my ($self) = @_;

    my $backup_info = Whostmgr::Backup::Restore::Legacy::get_user_backup_info_for_restore_type( $self->{'backup_user'}, $self->{'input'}->{'restoretype'} );

    return "$backup_info->{'source_dir'}/$backup_info->{'source_file'}";
}

1;
