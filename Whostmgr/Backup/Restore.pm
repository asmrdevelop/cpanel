package Whostmgr::Backup::Restore;

# cpanel - Whostmgr/Backup/Restore.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Whostmgr::Backup::Restore::Legacy ();
use Cpanel::Exception                 ();
use Cpanel::Output::Restore::HTML     ();

use Whostmgr::Func ();

use Whostmgr::Transfers::AccountRestoration ();
use Whostmgr::Transfers::RestrictedRestore  ();
use Whostmgr::Transfers::Session::Config    ();

use Try::Tiny;

my %LEGACY_DISABLERS = (
    'restorereseller' => { 'Reseller'      => { 'all'           => 1 } },
    'restoresubs'     => { 'Domains'       => { 'subdomains'    => 1 } },
    'restoreparked'   => { 'Domains'       => { 'parkeddomains' => 1 } },
    'restoreall'      => { 'Account'       => { 'all'           => 1 } },
    'createacct'      => { 'Account'       => { 'all'           => 1 } },
    'restoremail'     => { 'Mail'          => { 'all'           => 1 } },
    'restoremysql'    => { 'Mysql'         => { 'databases'     => 1 } },
    'restorepsql'     => { 'Postgres'      => { 'databases'     => 1 } },
    'restorebwdata'   => { 'BandwidthData' => { 'all'           => 1 } },
);

sub load_transfers_then_restorecpmove {
    my %opts = @_;

    my $path;
    if ( $opts{'file'} =~ m{/} || !$opts{'dir'} ) {
        $path = $opts{'file'};
    }
    elsif ( $opts{'dir'} ) {
        $path = "$opts{'dir'}/$opts{'file'}";
    }
    my $output_obj         = delete $opts{'output_obj'};
    my $percentage_coderef = delete $opts{'percentage_coderef'};
    my $disabled           = delete $opts{'disabled'} || {};

    # Convert legacy keys into the disabled structure
    # that Whostmgr::Transfers::AccountRestoration
    # expects
    foreach my $disabler ( keys %LEGACY_DISABLERS ) {
        if ( exists $opts{$disabler} && !$opts{$disabler} ) {
            foreach my $module ( keys %{ $LEGACY_DISABLERS{$disabler} } ) {
                foreach my $part ( keys %{ $LEGACY_DISABLERS{$disabler}->{$module} } ) {
                    $disabled->{$module}{$part} = 1;
                }
            }
            delete $opts{$disabler};
        }
    }

    if ( delete $opts{'skiphomedir'} ) {
        $disabled->{'Homedir'}{'all'}  = 1;
        $disabled->{'MailSync'}{'all'} = 1;
    }

    if ( !Whostmgr::Transfers::RestrictedRestore::available() && $opts{'unrestricted_restore'} == $Whostmgr::Transfers::Session::Config::RESTRICTED ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'Restricted Restore is not available in this version of [output,asis,cPanel].' );
    }

    my $account_restore_obj = Whostmgr::Transfers::AccountRestoration->new(
        'unrestricted_restore' => (
              $opts{'unrestricted_restore'}
            ? $Whostmgr::Transfers::Session::Config::UNRESTRICTED
            : $Whostmgr::Transfers::Session::Config::RESTRICTED
        ),
        'path'               => $path,
        'disabled'           => $disabled,
        'flags'              => \%opts,
        'output_obj'         => $output_obj,
        'percentage_coderef' => $percentage_coderef
    );

    local $@;
    my ( $status, $message ) = eval { $account_restore_obj->restore_package() };

    if ($@) {
        return wantarray ? ( 0, $@, $account_restore_obj ) : 0;
    }
    else {
        return wantarray ? ( $status, $message, $account_restore_obj ) : $status;
    }
}

sub restore_account {
    my (%args)                      = @_;
    my $restoretype                 = $args{'restoretype'} || '';
    my $user                        = $args{'user'};
    my $output_obj                  = $args{'output_obj'};
    my $restoreall                  = Whostmgr::Func::yesno( $args{'restoreall'} ) eq 'y'    ? 1 : 0;
    my $restoreip                   = Whostmgr::Func::yesno( $args{'restoreip'} ) eq 'y'     ? 1 : 0;
    my $restoremail                 = Whostmgr::Func::yesno( $args{'restoremail'} ) eq 'y'   ? 1 : 0;
    my $restoremysql                = Whostmgr::Func::yesno( $args{'restoremysql'} ) eq 'y'  ? 1 : 0;
    my $restorepsql                 = Whostmgr::Func::yesno( $args{'restorepsql'} ) eq 'y'   ? 1 : 0;
    my $restorebwdata               = Whostmgr::Func::yesno( $args{'restorebwdata'} ) eq 'y' ? 1 : 0;
    my $restoresubs                 = Whostmgr::Func::yesno( $args{'restoresubs'} ) eq 'y'   ? 1 : 0;
    my $mysql_dbs_to_restore        = $args{'mysql_dbs_to_restore'};
    my $pgsql_dbs_to_restore        = $args{'pgsql_dbs_to_restore'};
    my $overwrite_all_dbs           = $args{'overwrite_all_dbs'};
    my $overwrite_all_dbusers       = $args{'overwrite_all_dbusers'};
    my $overwrite_sameowner_dbs     = $args{'overwrite_sameowner_dbs'};
    my $overwrite_sameowner_dbusers = $args{'overwrite_sameowner_dbusers'};
    my $overwrite_with_delete       = $args{'overwrite_with_delete'};

    my $unrestricted_restore = $args{'unrestricted_restore'} ? 1 : 0;

    $user        =~ s/\.{2}|\///g;
    $restoretype =~ s/\.{2}|\///g;

    if ( !length $user ) {
        return 0, 'No user selected.';
    }

    if ( !length $restoretype ) {
        return 0, 'No restore type specified.';
    }

    my ( $backup_info, $err );
    try {
        $backup_info = Whostmgr::Backup::Restore::Legacy::get_user_backup_info_for_restore_type( $user, $restoretype );
    }
    catch {
        $err = $_;
    };

    if ($err) {
        return 0, Cpanel::Exception::get_string($err);
    }

    my ( $status, $statusmsg, $account_restore_obj ) = load_transfers_then_restorecpmove(
        'user'                        => $user,
        'file'                        => $backup_info->{'source_file'},
        'dir'                         => $backup_info->{'source_dir'},
        'createacct'                  => $restoreall,
        'ip'                          => $restoreip,
        'restoremail'                 => $restoremail,
        'restoremysql'                => $restoremysql,
        'restorepsql'                 => $restorepsql,
        'restorebwdata'               => $restorebwdata,
        'restoresubs'                 => $restoresubs,
        'mysql_dbs_to_restore'        => $mysql_dbs_to_restore,
        'pgsql_dbs_to_restore'        => $pgsql_dbs_to_restore,
        'overwrite_all_dbs'           => $overwrite_all_dbs,
        'overwrite_all_dbusers'       => $overwrite_all_dbusers,
        'overwrite_sameowner_dbs'     => $overwrite_sameowner_dbs,
        'overwrite_sameowner_dbusers' => $overwrite_sameowner_dbusers,
        'overwrite_with_delete'       => $overwrite_with_delete,

        'output_obj'           => ( $output_obj || Cpanel::Output::Restore::HTML->new() ),
        'unrestricted_restore' => $unrestricted_restore,
    );

    return ( $status, $statusmsg, $account_restore_obj );
}

1;
