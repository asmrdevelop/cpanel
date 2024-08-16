package Whostmgr::API::1::Transfers;

# cpanel - Whostmgr/API/1/Transfers.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Whostmgr::ACLS          ();
use Whostmgr::API::1::Utils ();

use Cpanel::Exception  ();
use Cpanel::LoadModule ();

use constant NEEDS_ROLE => {
    abort_transfer_session                    => undef,
    analyze_transfer_session_remote           => undef,
    available_transfer_modules                => undef,
    create_remote_root_transfer_session       => undef,
    create_remote_user_transfer_session       => undef,
    delete_account_archives                   => undef,
    enqueue_transfer_item                     => undef,
    fetch_transfer_session_log                => undef,
    get_transfer_session_state                => undef,
    pause_transfer_session                    => undef,
    restore_modules_summary                   => undef,
    retrieve_transfer_session_remote_analysis => undef,
    start_transfer_session                    => undef,
    transfer_module_schema                    => undef,
    start_local_cpmove_restore                => undef,
};

use Try::Tiny;

my $locale;

sub _locale {
    require Cpanel::Locale;
    return $locale ||= Cpanel::Locale->get_handle();
}

sub start_transfer_session {
    my ( $args, $metadata ) = @_;
    my $transfer_session_id = $args->{'transfer_session_id'};

    require Whostmgr::Transfers::Session::Start;
    my ( $start_ok, $pid_or_error ) = Whostmgr::Transfers::Session::Start::start_transfer_session($transfer_session_id);

    if ($start_ok) {
        @{$metadata}{qw(result reason)} = qw( 1 OK );
        return { 'pid' => $pid_or_error };
    }
    else {
        @{$metadata}{qw(result reason)} = ( 0, _locale()->maketext( "The system failed to start the transfer session “[_1]” because of an error: [_2]", $transfer_session_id, $pid_or_error ) );
    }
    return;
}

sub get_transfer_session_state {
    my ( $args, $metadata ) = @_;
    my $transfer_session_id = $args->{'transfer_session_id'};

    require Whostmgr::Transfers::Session::Setup;
    my ( $setup_ok, $session_obj ) = Whostmgr::Transfers::Session::Setup::setup_session_obj( { 'id' => $transfer_session_id } );
    if ( !$setup_ok ) {
        @{$metadata}{qw(result reason)} = ( $setup_ok, $session_obj );
        return;
    }

    my $state_name = $session_obj->get_session_state_name();
    $session_obj->disconnect();    # TP TASK 20767 disconnect before global destruct

    if ( length $state_name ) {
        @{$metadata}{qw(result reason)} = qw( 1 OK );
        return { 'state_name' => $state_name };
    }
    else {
        @{$metadata}{qw(result reason)} = ( 0, _locale()->maketext("The system failed to fetch the transfer session state.") );
        return;
    }
}

sub pause_transfer_session {
    my ( $args, $metadata ) = @_;
    return _set_transfer_session_state( 'pause', 'start_pause', $args, $metadata );
}

sub abort_transfer_session {
    my ( $args, $metadata ) = @_;
    return _set_transfer_session_state( 'abort', 'start_abort', $args, $metadata );
}

sub _set_transfer_session_state {
    my ( $state_name, $state_func_name, $args, $metadata ) = @_;

    my $transfer_session_id = $args->{'transfer_session_id'};

    require Whostmgr::Transfers::Session::Setup;
    my ( $setup_ok, $session_obj ) = Whostmgr::Transfers::Session::Setup::setup_session_obj( { 'id' => $transfer_session_id } );
    if ( !$setup_ok ) {
        @{$metadata}{qw(result reason)} = ( $setup_ok, $session_obj );
        return;
    }

    my $op_ok = $session_obj->can($state_func_name)->($session_obj);
    $session_obj->disconnect();    # TP TASK 20767 disconnect before global destruct

    if ($op_ok) {
        @{$metadata}{qw(result reason)} = qw( 1 OK );
    }
    else {
        @{$metadata}{qw(result reason)} = ( 0, _locale()->maketext( "The system failed to “[_1]” the transfer session.", $state_name ) );
    }
    return;
}

sub create_remote_root_transfer_session {
    my ( $args, $metadata ) = @_;

    require Whostmgr::Transfers::Session::Preflight::RemoteRoot::Create;
    require Whostmgr::Transfers::Session::Preflight::RemoteRoot::Analyze;

    local $SIG{'__WARN__'} = sub ($err) {
        $err =~ s<\s+\z><>;

        $metadata->add_warning($err);
    };

    my ( $create_ok, $session_id, $create_rawout ) = Whostmgr::Transfers::Session::Preflight::RemoteRoot::Create::create_remote_root_transfer_session($args);
    if ( !$create_ok ) {
        @{$metadata}{qw(result reason)} = ( $create_ok, $session_id );
        return;
    }

    my ( $analyze_ok, $analyze_msg, $analyze_rawout ) = Whostmgr::Transfers::Session::Preflight::RemoteRoot::Analyze::analyze_remote( { transfer_session_id => $session_id } );
    if ( !$analyze_ok ) {
        @{$metadata}{qw(result reason)} = ( $analyze_ok, $analyze_msg );
        return;
    }

    @{$metadata}{qw(result reason)} = qw( 1 OK );

    return { 'transfer_session_id' => $session_id, 'create_rawout' => $create_rawout, 'analyze_rawout' => $analyze_rawout };
}

sub analyze_transfer_session_remote {
    my ( $args, $metadata ) = @_;

    require Whostmgr::Transfers::Session::Preflight::RemoteRoot::Analyze;
    my $transfer_session_id = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'transfer_session_id' );

    my ( $analyze_ok, $analyze_msg ) = Whostmgr::Transfers::Session::Preflight::RemoteRoot::Analyze::analyze_remote( { transfer_session_id => $transfer_session_id } );
    if ( !$analyze_ok ) {
        @{$metadata}{qw(result reason)} = ( $analyze_ok, $analyze_msg );
        return;
    }

    @{$metadata}{qw(result reason)} = qw( 1 OK );

    return;
}

sub retrieve_transfer_session_remote_analysis {
    my ( $args, $metadata ) = @_;

    require Whostmgr::Transfers::Session::Preflight::RemoteRoot::Results;
    my ( $analyze_ok, $analyze_msg ) = Whostmgr::Transfers::Session::Preflight::RemoteRoot::Results::retrieve_analysis($args);
    if ( !$analyze_ok ) {
        @{$metadata}{qw(result reason)} = ( $analyze_ok, $analyze_msg );
        return;
    }
    @{$metadata}{qw(result reason)} = qw( 1 OK );
    return $analyze_msg;
}

sub create_remote_user_transfer_session {
    my ( $args, $metadata ) = @_;

    require Whostmgr::Transfers::Session::Preflight::RemoteUser::Create;
    my ( $create_ok, $session_id ) = Whostmgr::Transfers::Session::Preflight::RemoteUser::Create::create_remote_user_transfer_session($args);
    if ( !$create_ok ) {
        @{$metadata}{qw(result reason)} = ( $create_ok, $session_id );
        return;
    }

    @{$metadata}{qw(result reason)} = qw( 1 OK );

    return { 'transfer_session_id' => $session_id };
}

sub available_transfer_modules {
    my ( $args, $metadata ) = @_;

    require Whostmgr::Transfers::Session::Items;
    my $available = Whostmgr::Transfers::Session::Items::available();

    @{$metadata}{qw(result reason)} = qw( 1 OK );

    return { 'modules' => $available };
}

sub transfer_module_schema {
    my ( $args, $metadata ) = @_;

    my $module = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'module' );

    require Whostmgr::Transfers::Session::Items;
    my ( $schema_ok, $schema ) = Whostmgr::Transfers::Session::Items::schema($module);

    if ($schema_ok) {
        @{$metadata}{qw(result reason)} = qw( 1 OK );
        return { 'schema' => $schema };
    }
    else {
        @{$metadata}{qw(result reason)} = ( $schema_ok, $schema );
        return;
    }
}

sub enqueue_transfer_item {
    my ( $args, $metadata ) = @_;

    foreach my $param (qw(transfer_session_id module)) {
        unless ( defined $args->{$param} ) {
            die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $param ] );
        }
    }

    my $transfer_session_id = delete $args->{'transfer_session_id'};
    my $module              = delete $args->{'module'};

    require Whostmgr::Transfers::Session::Items;
    my $available = Whostmgr::Transfers::Session::Items::available();

    if ( !$available->{$module} ) {
        @{$metadata}{qw(result reason)} = ( 0, _locale()->maketext( "The transfer session module “[_1]” does not exist.", $module ) );
        return;
    }

    my $object_type = "Whostmgr::Transfers::Session::Items::$module";
    Cpanel::LoadModule::load_perl_module($object_type);

    if ( !( "$object_type"->allow_non_root_enqueue() || Whostmgr::ACLS::hasroot() ) ) {
        @{$metadata}{qw(result reason)} = ( 0, _locale()->maketext( "The transfer session module “[_1]” can not be enqueued as a non-root user.", $module ) );
        return;
    }

    require Whostmgr::Transfers::Session::Setup;
    my ( $setup_ok, $session_obj ) = Whostmgr::Transfers::Session::Setup::setup_session_obj( { 'id' => $transfer_session_id } );
    if ( !$setup_ok ) {
        @{$metadata}{qw(result reason)} = ( $setup_ok, $session_obj );
        return;
    }

    $object_type->prevalidate_or_die( $session_obj, $args );

    my ( $enqueue, $err_obj );
    try {
        $enqueue = $session_obj->enqueue( $module, $args );
    }
    catch {
        $err_obj = $_;
    };

    $session_obj->disconnect();    # TP TASK 20767 disconnect before global destruct

    if ($enqueue) {
        @{$metadata}{qw(result reason)} = qw( 1 OK );
    }
    else {
        @{$metadata}{qw(result reason)} = ( 0, Cpanel::Exception::get_string($err_obj) );
    }
    return;
}

sub fetch_transfer_session_log {
    my ( $args, $metadata ) = @_;

    my $transfer_session_id = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'transfer_session_id' );
    my $logfile             = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'logfile' );

    require Whostmgr::Transfers::Session::Setup;
    my ( $setup_ok, $session_obj ) = Whostmgr::Transfers::Session::Setup::setup_session_obj( { 'id' => $transfer_session_id } );

    if ( !$setup_ok ) {
        @{$metadata}{qw(result reason)} = ( $setup_ok, $session_obj );
        return;
    }

    require Cpanel::LogTailer::Renderer::Scalar;
    my $renderer = Cpanel::LogTailer::Renderer::Scalar->new();
    require Whostmgr::Transfers::Session::Logs;
    my $log_obj = Whostmgr::Transfers::Session::Logs->new( 'id' => $transfer_session_id, 'renderer' => $renderer );

    $log_obj->tail_log( $logfile, 0, { 'one_loop' => 1 } );

    @{$metadata}{qw(result reason)} = qw( 1 OK );
    return { 'log' => $$renderer };
}

sub restore_modules_summary {
    my ( $args, $metadata ) = @_;

    Cpanel::LoadModule::load_perl_module('Whostmgr::Transfers::AccountRestoration');

    my $module_summaries = 'Whostmgr::Transfers::AccountRestoration'->new()->get_module_summaries();

    @{$metadata}{qw(result reason)} = qw( 1 OK );

    return { 'modules' => $module_summaries };
}

sub delete_account_archives {
    my ( $args, $metadata ) = @_;

    my $username   = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'user' );
    my $mountpoint = Whostmgr::API::1::Utils::get_length_argument( $args, 'mountpoint' );

    require Cpanel::SafeRun::Object;
    require Cpanel::ConfigFiles;
    my $run = Cpanel::SafeRun::Object->new_or_die(
        program => "$Cpanel::ConfigFiles::CPANEL_ROOT/scripts/unpkgacct",
        args    => [ $username, $mountpoint // () ],
    );

    if ( length $run->stdout() ) {
        $metadata->{'output'}{'messages'} = [ split m<\n+>, $run->stdout() ];
    }
    if ( length $run->stderr() ) {
        $metadata->{'output'}{'warnings'} = [ $run->stderr() ];
    }

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return;
}

sub start_local_cpmove_restore {

    my ( $args, $metadata ) = @_;

    my $opts_hr = { initiator => "start_local_cpmove_restore" };

    $opts_hr->{cpmovepath} = Whostmgr::API::1::Utils::get_length_required_argument( $args, "cpmovepath" );

    $opts_hr->{overwrite}      = $args->{overwrite}        || 0;
    $opts_hr->{dedicated_ip}   = $args->{dedicated_ip}     || 0;
    $opts_hr->{restricted}     = $args->{restricted}       || 0;
    $opts_hr->{update_a_rec}   = $args->{update_a_records} || "all";
    $opts_hr->{delete_archive} = $args->{delete_archive}   || 0;

    require Whostmgr::Transfers::Utils::LinkedNodes;

    my @passthrough_args = (
        'username',
        values %Whostmgr::Transfers::Utils::LinkedNodes::WORKER_TYPE_CAPABILITY_PARAMETER,
    );

    $opts_hr->{$_} = $args->{$_} for @passthrough_args;

    require Whostmgr::Transfers::LocalRestore;
    my $transfer_session_id = Whostmgr::Transfers::LocalRestore::start_local_cpmove_restore($opts_hr);

    $metadata->set_ok();

    return { transfer_session_id => $transfer_session_id };
}

1;
