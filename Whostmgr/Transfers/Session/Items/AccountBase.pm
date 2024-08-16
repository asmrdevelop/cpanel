package Whostmgr::Transfers::Session::Items::AccountBase;

# cpanel - Whostmgr/Transfers/Session/Items/AccountBase.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent qw(
  Whostmgr::Transfers::Session::Items::AccountRestoreBase
  Whostmgr::Transfers::Session::Items::Schema::AccountBase
);

our $VERSION = '1.5';

use Scalar::Util ();

use Whostmgr::Backup::Restore ();

use Cpanel::Exception          ();
use Cpanel::AcctUtils::Account ();

use Whostmgr::Transfers::Utils::LinkedNodes ();

use constant _custom_account_restore_args => ();
use constant _PRIVILEGE_LEVEL             => "root";

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
              _remove_local_cpmove_files
            ),
            ( $self->can('post_restore') ? 'post_restore' : () )
        ],
        ['tear_down_restore'],
        $Whostmgr::Transfers::Session::Item::ABORTABLE,
    );
}

# cf. Whostmgr::Transfers::Session::Item’s prevalidate_or_die().
sub _prevalidate ( $class, $session_obj, $input_hr ) {
    my $flag_name = 'live_transfer';

    if ( $input_hr->{$flag_name} ) {
        require Cpanel::Hostname::Resolution;

        if ( Cpanel::Hostname::Resolution->load() ) {
            $class->_prevalidate_live_transfer( $session_obj, $input_hr );
        }
        else {
            require Cpanel::Hostname;
            my $hostname = Cpanel::Hostname::gethostname();

            die Cpanel::Exception::create( 'InvalidParameter', 'This server’s hostname ([_1]) does not resolve to a local [asis,IP] address. The “[_2]” option requires proper hostname resolution. Fix the hostname resolution, or disable the “[_2]” option.', [ $hostname, $flag_name ] );
        }
    }

    return $class->SUPER::_prevalidate( $session_obj, $input_hr );
}

sub _prevalidate_live_transfer ( $, $, $ ) { }

sub _validate_restore_package_input {
    my ($self) = @_;

    return $self->validate_input( [ 'detected_remote_user', [ 'input', ['cpmovefile'] ] ] );
}

# NB: This restores an *account*, not a plan/package.
sub _restore_package {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ($self) = @_;

    # Case 176937 - restorepkg --force should ignore disk space checks
    my $ignore_disk_space = 0;
    if ( exists $self->{'session_obj'} ) {
        $ignore_disk_space = $self->{'session_obj'}->{'ignore_disk_space'} if ( exists $self->{'session_obj'}->{'ignore_disk_space'} );
    }

    my $disabled = {};

    # When they use --disable on the restorepkg command line
    # we want to disable everything in the restore module
    if ( defined $self->{'input'}{'disabled'} ) {
        for ( split /,/, $self->{'input'}{'disabled'} ) { $disabled->{$_}{'all'} = 1 }
    }

    my $remote_cpversion = $self->session()->get_data( 'remote', 'type' );
    $remote_cpversion &&= $remote_cpversion =~ m<\AWHM>;
    $remote_cpversion &&= $self->session()->get_data( 'remote', 'cpversion' );

    my $weak_self = $self;
    Scalar::Util::weaken($weak_self);

    my %restore_args = (
        'restore_type'                => $self->_PRIVILEGE_LEVEL(),
        'user'                        => $self->{'local_user'},
        'olduser'                     => $self->{'detected_remote_user'},
        'output_obj'                  => $self->{'output_obj'},
        'file'                        => $self->{'input'}->{'cpmovefile'},
        'dir'                         => $self->{'input'}->{'copypoint'},
        'force'                       => ( $self->{'force'}                 ? 1 : 0 ),
        'restorereseller'             => ( $self->{'skipres'}               ? 0 : 1 ),
        'restorebwdata'               => ( $self->{'input'}->{'skipbwdata'} ? 0 : 1 ),
        'restoremysql'                => ( $self->{'input'}->{'skipacctdb'} ? 0 : 1 ),
        'restorepsql'                 => ( $self->{'input'}->{'skipacctdb'} ? 0 : 1 ),
        'restoreparked'               => 1,
        'restoresubs'                 => ( $self->{'input'}->{'skipsubdomains'}              ? 0 : 1 ),
        'createacct'                  => ( $self->{'input'}->{'skipaccount'}                 ? 0 : 1 ),
        'overwrite_all_dbs'           => ( $self->{'input'}->{'overwrite_all_dbs'}           ? 1 : 0 ),
        'overwrite_all_dbusers'       => ( $self->{'input'}->{'overwrite_all_dbusers'}       ? 1 : 0 ),
        'overwrite_sameowner_dbs'     => ( $self->{'input'}->{'overwrite_sameowner_dbs'}     ? 1 : 0 ),
        'overwrite_sameowner_dbusers' => ( $self->{'input'}->{'overwrite_sameowner_dbusers'} ? 1 : 0 ),
        'overwrite_with_delete'       => ( $self->{'input'}->{'overwrite_with_delete'}       ? 1 : 0 ),
        'restoremail'                 => ( $self->{'input'}->{'skipemail'}                   ? 0 : 1 ),
        'skiphomedir'                 => ( $self->{'input'}->{'skiphomedir'}                 ? 1 : 0 ),
        'shared_mysql_server'         => ( $self->{'input'}->{'shared_mysql_server'}         ? 1 : 0 ),

        # HB-6430
        'keep_local_cpuser_values' => [ split( ',', $self->{'input'}{'keep_local_cpuser_values'} || '' ) ],

        # This is what the remote host reports as its hostname.
        # That’s probably less useful than “remote_host”, which is
        # the actual name or IP address that we used to reach the
        # source server.
        'remote_hostname' => scalar( $self->session()->get_data( 'remote_data', 'hostname' ) ),

        # This is what the caller entered as the source server’s name or IP.
        'remote_host' => $self->{'remote_info'}{'sshhost'},

        'remote_cpversion'     => $remote_cpversion,
        'ip'                   => ( $self->{'input'}->{'ip'}                                               ? 1                                             : 0 ),
        'replaceip'            => ( $self->{'input'}->{'replaceip'}                                        ? $self->{'input'}->{'replaceip'}               : 'all' ),
        'customip'             => ( $self->{'input'}->{'customip'}                                         ? $self->{'input'}->{'customip'}                : undef ),
        'pre_dns_restore'      => ( $self->{'input'}->{'xferpoint'} || $self->{'input'}->{'live_transfer'} ? sub { $weak_self->_run_remote_xferpoint(@_) } : undef ),
        'live_transfer'        => ( $self->{'input'}->{'live_transfer'}                                    ? 1                                             : 0 ),
        'unrestricted_restore' => ( $self->{'options'}->{'unrestricted'}                                   ? 1                                             : 0 ),
        'extractname'          => "cpmove-" . $self->{'detected_remote_user'},
        'percentage_coderef'   => sub {
            my ($pct) = @_;
            my $relative_pct = int( 10 + ( $pct * .8 ) );

            $weak_self->set_percentage($relative_pct);
        },
        (
            $self->{'can_stream'}
            ? (
                'stream' => {

                    'version'    => 1,
                    'rsync'      => ( $self->{'can_rsync'} ? 1 : 0 ),
                    'sourceuser' => $self->{'detected_remote_user'},
                    'use_ssl'    => $self->{'options'}->{'ssl'},
                    'host'       => $self->{'remote_info'}->{'sshhost'},
                    'user'       => $self->{'authinfo'}->{'whmuser'},
                    'pass'       => $self->{'authinfo'}->{'whmpass'},
                    'accesshash' => $self->{'authinfo'}->{'accesshash_pass'},

                }
              )
            : ()
        ),
        'ignore_disk_space' => $ignore_disk_space,
        'disabled'          => $disabled,

        (
            map {
                $_ => $self->{'input'}{$_},
            } values %Whostmgr::Transfers::Utils::LinkedNodes::WORKER_TYPE_CAPABILITY_PARAMETER
        ),

        $self->_custom_account_restore_args(),
    );

    # Fail safe for API users
    if ( $restore_args{'user'} ne $restore_args{'olduser'} ) {
        if ( $restore_args{'force'} && ( Cpanel::AcctUtils::Account::accountexists( $restore_args{'user'} ) || Cpanel::AcctUtils::Account::accountexists( $restore_args{'olduser'} ) ) ) {
            return (
                0,
                $self->_locale()->maketext('Account Restore Failed: You cannot overwrite an account if you change the account’s username.'),
            );
        }
    }

    my ( $restore_status, $restore_message );

    ( $restore_status, $restore_message, $self->{'account_restore_obj'} ) = Whostmgr::Backup::Restore::load_transfers_then_restorecpmove(%restore_args);

    return ( $restore_status, $restore_status ? $restore_message : $self->_locale()->maketext( "Account Restore Failed: “[_1]”", $restore_message ) );
}

sub _display_options {
    my ($self) = @_;
    $self->set_percentage(10);

    print $self->_locale()->maketext( "Restore File: [_1]", $self->get_restore_source_path() );
    print $self->{'skipres'}
      ? $self->_locale()->maketext('Restore Reseller Privs: no') . "\n"
      : $self->_locale()->maketext('Restore Reseller Privs: yes') . "\n";
    print $self->{'options'}->{'unrestricted'}
      ? $self->_locale()->maketext('Restricted mode: no') . "\n"
      : $self->_locale()->maketext('Restricted mode: yes') . "\n";

    my $live_type = $self->_locale()->maketext("no");

    if ( $self->{'input'}->{'xferpoint'} && !$self->{'input'}->{'live_transfer'} ) {
        $live_type = $self->_locale()->maketext( "legacy mode (“[_1]”)", $self->_locale()->maketext('Express Transfer') );
    }
    elsif ( $self->{'input'}->{'live_transfer'} ) {
        $live_type = $self->_locale()->maketext("yes");
    }

    print $self->_locale()->maketext( 'Live transfer: [_1]', $live_type ) . "\n";

    return ( 1, 'OK' );
}

sub _restore_init {
    my ($self) = @_;

    $self->session_obj_init();

    $self->{'local_user'}           = $self->{'input'}->{'localuser'};
    $self->{'detected_remote_user'} = $self->{'input'}->{'detected_remote_user'} || $self->item();    # self->item() FKA $self->{'input'}->{'user'};

    $self->{'skipres'} = $self->{'input'}->{'skipres'};
    $self->{'skipres'} = $self->{'options'}->{'skipres'} if !defined $self->{'skipres'};
    $self->{'skipres'} = 1                               if !$self->{'options'}->{'unrestricted'};

    $self->{'force'} = $self->{'input'}->{'force'};
    $self->{'force'} = 0 if !$self->{'options'}->{'unrestricted'};

    return $self->validate_input( [qw(session_obj remote_info options session_info output_obj local_user detected_remote_user skipres force)] );
}

sub _run_remote_xferpoint { }

sub tear_down_restore {
    my ($self) = @_;

    $self->_remove_local_cpmove_files();

    if ( $self->{'orig_cwd'} ) {
        return chdir( $self->{'orig_cwd'} );
    }

    return 1;
}

sub _remove_local_cpmove_files {
    my ($self) = @_;

    # only removed for remote restores
    #
    return ( 1, 'ok' );
}

sub get_restore_source_path {
    my ($self) = @_;

    return ( $self->{'input'}->{'copypoint'} ? "$self->{'input'}->{'copypoint'}/$self->{'input'}->{'cpmovefile'}" : $self->{'input'}->{'cpmovefile'} );
}

sub local_item {
    my ($self) = @_;

    return $self->{'input'}->{'localuser'};
}

1;
