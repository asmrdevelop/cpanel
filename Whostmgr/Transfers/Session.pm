package Whostmgr::Transfers::Session;

# cpanel - Whostmgr/Transfers/Session.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Time                            ();
use Cpanel::Exception                       ();
use Cpanel::LoadModule                      ();
use Cpanel::LoadFile                        ();
use Cpanel::FileUtils::TouchFile            ();
use Cpanel::FileUtils::Write                ();
use Cpanel::WrapOutputFH                    ();
use Cpanel::Session::Encoder                ();
use Cpanel::Sys::Hostname                   ();
use Cpanel::Rand::Get                       ();
use Cpanel::Output                          ();
use Cpanel::ProcessCheck::Running           ();
use Whostmgr::Transfers::SessionBase        ();
use Whostmgr::Transfers::Session::Logs      ();
use Whostmgr::Transfers::Session::Config    ();
use Whostmgr::Transfers::Session::Constants ();

use Try::Tiny;

use parent qw( Whostmgr::Transfers::SessionBase );

my $locale;

# Items are processed in ASC order

our $PASSWORD_MATCH = 'pass';

our %ITEMTYPE_IDS = reverse %Whostmgr::Transfers::Session::Config::ITEMTYPE_NAMES;

my $logger;

sub get_output_obj {
    my ($self) = @_;

    return $self->{'output_obj'} || die Cpanel::Exception::create( 'AttributeNotSet', 'The attribute “[_1]” needs to be set before calling “[_2]”.', [ 'output_obj', 'get_output_obj' ] );
}

sub set_output_obj {
    my ( $self, $output_obj ) = @_;

    $self->{'output_obj'} = $output_obj;

    return 1;
}

sub set_pid {
    my ( $self, $pid ) = @_;

    return $self->_set_session_pid( $self->id(), $pid );
}

sub get_pid {
    my ($self) = @_;

    return $self->_get_session_pid( $self->id() );
}

sub get_session_state {
    my ($self) = @_;

    return $self->_get_session_state( $self->id() );
}

sub get_session_state_name {
    my ($self) = @_;

    return $self->_get_session_state_name( $self->id() );
}

sub get_source_host {
    my ($self) = @_;

    return $self->SUPER::get_source_host( $self->id() );
}

sub set_source_host {
    my ( $self, $source_host ) = @_;

    return $self->SUPER::set_source_host( $self->id(), $source_host );
}

sub get_queue_counts {
    my ($self) = @_;

    my $queue_table = $self->_session_table('queue');
    return $self->_get_queue_query("select COUNT(*) from $queue_table");
}

sub get_queue_sizes {
    my ($self) = @_;

    my $queue_table = $self->_session_table('queue');
    return $self->_get_queue_query("select SUM(size) from $queue_table");
}

sub _get_queue_query {
    my ( $self, $query ) = @_;
    my $queue_table = $self->_session_table('queue');
    my $row         = $self->session_sql( 'selectrow_arrayref', [$query] );

    my $queues = $self->queueinfo();
    my $result = {};
    foreach my $queue ( keys %{$queues} ) {
        $result->{$queue} = $row->[0];
    }

    return $result;
}

sub get_session_details {
    my ($self) = @_;
    return $self->SUPER::get_session_details( $self->id() );
}

sub get_starttime_unix {
    my ($self) = @_;
    return $self->SUPER::get_starttime_unix( $self->id() );
}

sub get_endtime_unix {
    my ($self) = @_;
    return $self->SUPER::get_endtime_unix( $self->id() );
}

sub is_running {
    my ($self) = @_;

    my $pid = $self->_get_session_pid( $self->id() );

    return $self->transfer_pid_is_running($pid);
}

sub transfer_pid_is_running {
    my ( $self, $pid ) = @_;

    my $id = $self->id();

    return 0 if !$pid;

    local $@;
    return eval { Cpanel::ProcessCheck::Running->new( 'user' => 'root', 'pid' => $pid, 'pattern' => qr<\Q$id\E> )->check_all() };
}

sub is_complete {
    my ($self) = @_;

    my $session_id = $self->id();

    my $session_completed_file = $Whostmgr::Transfers::Session::Config::SESSION_DIR . '/' . $session_id . '/master.log';

    return -e $session_completed_file ? 1 : 0;
}

sub get_pids {
    my ($self)      = @_;
    my $queue_table = $self->_session_table('queue');
    my $rows        = $self->session_sql( 'selectall_arrayref', ["select pid from $queue_table where pid > 0 /* start_abort */;"] );
    my @pids;
    if ($rows) {
        @pids = map { $_->[0] } @{$rows};
    }
    return @pids;
}

# Session State Control

sub start_abort {
    my ($self) = @_;

    return 0 if !$self->can_change_state('ABORTING');

    if ( $self->is_running() ) {
        my $queue_table = $self->_session_table('queue');
        my @pids_to_kill;
        if ( my $rows = $self->session_sql( 'selectall_arrayref', ["select pid from $queue_table where pid > 0 /* start_abort */;"] ) ) {
            push @pids_to_kill, map { $_->[0] } @{$rows};
        }

        $self->_signal_transfer_processes_and_children_to_abort(@pids_to_kill);
    }
    elsif ( !$self->is_paused() ) {
        $self->mark_session_failed();
        return 1;
    }

    Cpanel::FileUtils::TouchFile::touchfile( $self->_session_aborting_file() );

    $self->SUPER::start_abort( $self->id() );

    if ( !$self->is_running() ) {
        $self->mark_session_aborted();
    }

    return 1;

}

sub complete_abort {
    my ($self) = @_;

    if ( rename( $self->_session_aborting_file(), $self->_session_abort_file() ) ) {
        $self->mark_session_aborted();
        return 1;
    }

    return;
}

sub complete_pause {
    my ($self) = @_;

    if ( rename( $self->_session_pausing_file(), $self->_session_pause_file() ) ) {
        $self->SUPER::complete_pause( $self->id() );
        return 1;
    }

    return;
}

sub start_pause {
    my ($self) = @_;

    if ( !$self->can_change_state('PAUSING') ) {
        return 0;
    }
    elsif ( !$self->is_running() ) {
        $self->mark_session_failed();
        return 1;
    }
    elsif ( !$self->is_paused() ) {
        Cpanel::FileUtils::TouchFile::touchfile( $self->_session_pausing_file() );

        $self->SUPER::start_pause( $self->id() );
        return 1;
    }

    return 0;
}

my %ABORTABLE_STATES = map { $_ => undef } (
    'PENDING',
    'RUNNING',
    'PAUSING',
    'PAUSED',
);

sub can_change_state {
    my ( $self, $target_state, $current_state ) = @_;

    $current_state ||= $Whostmgr::Transfers::SessionBase::SESSION_STATE_NAMES{ $self->get_session_state() };

    if ( $current_state eq $target_state ) {
        return 1;
    }
    elsif ( $target_state eq 'FAILED' ) {
        return 1;
    }
    elsif ( $target_state eq 'ABORTED' ) {
        return $current_state eq 'ABORTING' ? 1 : 0;
    }
    elsif ( $target_state eq 'COMPLETED' ) {
        return $current_state eq 'RUNNING' ? 1 : 0;
    }
    elsif ( $target_state eq 'PAUSED' ) {
        return $current_state eq 'PAUSING' ? 1 : 0;
    }
    elsif ( $target_state eq 'ABORTING' ) {
        return exists( $ABORTABLE_STATES{$current_state} ) ? 1 : 0;
    }
    elsif ( $target_state eq 'PAUSING' ) {
        return $current_state eq 'RUNNING' ? 1 : 0;
    }
    elsif ( $target_state eq 'RUNNING' ) {
        return ( $current_state eq 'PAUSED' || $current_state eq 'PENDING' ) ? 1 : 0;
    }
    return 0;
}

sub unpause {
    my ($self) = @_;

    return 0 if !$self->can_change_state('RUNNING');

    my $session_id = $self->id();

    my $session_pause_file = $self->_session_pause_file();

    unlink($session_pause_file);

    if ( !$self->is_paused() ) {
        $self->SUPER::resume($session_id);
        return 1;
    }

    return 0;
}

sub delete {
    my ($self) = @_;

    $self->logs()->delete_log();

    return if !$self->_delete_session();

    return 1;
}

sub start {
    my ($self) = @_;

    return 0 if !$self->can_change_state('RUNNING');

    return $self->SUPER::resume( $self->id() );
}

sub is_pausing {
    my ($self) = @_;

    my $session_id = $self->id();

    my $session_pausing_file = $self->_session_pausing_file();

    return -e $session_pausing_file ? 1 : 0;
}

sub is_paused {
    my ($self) = @_;

    my $session_id = $self->id();

    my $session_pausing_file = $self->_session_pausing_file();
    my $session_pause_file   = $self->_session_pause_file();

    return -e $session_pause_file || -e $session_pausing_file ? 1 : 0;
}

sub is_aborting {
    my ($self) = @_;

    my $session_id = $self->id();

    my $session_aborting_file = $self->_session_aborting_file();

    return -e $session_aborting_file ? 1 : 0;
}

sub is_aborted {
    my ($self) = @_;

    my $session_id = $self->id();

    my $session_aborting_file = $self->_session_aborting_file();
    my $session_abort_file    = $self->_session_abort_file();

    return -e $session_abort_file || -e $session_aborting_file ? 1 : 0;
}

sub mark_session_completed {
    my ($self) = @_;

    my $sessionid = $self->id();

    unlink( $self->_session_pausing_file(), $self->_session_pause_file(), $self->_session_aborting_file() );

    my $session_table = $self->_session_table('session');

    $self->session_do("UPDATE $session_table SET keyvalue=null where keyname LIKE '%${PASSWORD_MATCH}%';");

    # Move away the log file
    $self->logs()->mark_session_completed();

    return $self->SUPER::mark_session_completed($sessionid);
}

sub mark_session_failed {
    my ($self) = @_;

    $self->_offline_master_message('fail') if !$self->is_running();

    $self->mark_session_completed();

    return $self->SUPER::mark_session_failed( $self->id() );
}

sub mark_session_aborted {
    my ($self) = @_;

    $self->_offline_master_message('abort') if !$self->is_running();

    $self->mark_session_completed();

    Cpanel::FileUtils::TouchFile::touchfile( $self->_session_abort_file() );

    return $self->SUPER::complete_abort( $self->id() );
}

sub _offline_master_message {
    my ( $self, $message ) = @_;

    my $log_fh       = $self->logs()->open_master_log_file();
    my $error_log_fh = $self->logs()->open_master_error_log_file();

    $self->exec_with_output_directed_to_fh(
        [ $log_fh, $error_log_fh ],
        sub {
            $self->output_message( 'control', { 'action' => $message, 'child_number' => 0 } );
        }
    );

    return 1;
}

sub _session_abort_file {
    my ($self) = @_;
    return $self->_session_state_file('abort');

}

sub _session_aborting_file {
    my ($self) = @_;

    #
    # When an abort operation is requested the system will
    # create a file called '.abort'
    #
    # When the abort operation is completed the file
    # will be renamed to 'abort'
    #
    return $self->_session_state_file('.abort');

}

sub _session_pause_file {
    my ($self) = @_;
    return $self->_session_state_file('pause');

}

sub _session_pausing_file {
    my ($self) = @_;

    #
    # When a pause operation is requested the system will
    # create a file called '.pause'
    #
    # When the pause operation is completed the file
    # will be renamed to 'pause'
    #
    return $self->_session_state_file('.pause');

}

sub _session_state_file {
    my ( $self, $file ) = @_;

    my $session_id = $self->id();
    return $Whostmgr::Transfers::Session::Config::SESSION_DIR . '/' . $session_id . '/' . $file;
}

# end state control

sub empty_queues {
    my ( $self, $queues ) = @_;

    foreach my $queue ( @{$queues} ) {
        if ( $self->table_exists( $self->_unquoted_session_table($queue) ) ) {
            my $ok = $self->_empty_queue($queue);
            return $ok if !$ok;
        }
    }

    return 1;
}

#
# This can generate an exception.
# be sure they are trapped and handled
#
# Arguments:
#   - $item_type corresponds to a schema name, e.g., Whostmgr::Transfers::Session::Items::Schema::AccountBase
#   - $data corresponds with 'keys' from that schema
#   - $state .. ?
#
sub enqueue {
    my ( $self, $item_type, $data, $state ) = @_;

    my $key              = $self->_get_item_primary_key($item_type);
    my $prerequisite_key = $self->_get_item_prerequisite_key($item_type);

    $self->_validate_enqueued_data_against_schema( $item_type, $data );

    # Create the table if it does not exist
    # We used to pre-create them all, however
    # as we have added more Transfer::Session::Items
    # it became very inefficent when most transfer types
    # only use one type.
    if ( !$self->table_exists( $self->_unquoted_session_table($item_type) ) ) {

        my @all_schema = $self->_generate_schema_for_tables( { $item_type => $self->_get_schema($item_type) } );
        foreach my $schema (@all_schema) {
            $self->session_do($schema)
              || die Cpanel::Exception::create( 'Database::TableCreationFailed', 'The system was unable to create the schema for the table “[_1]” for session “[_2]”.', [ $item_type, $self->id() ] );
        }
    }

    if ( $self->item_exists( $item_type, $data->{$key} ) ) {
        die Cpanel::Exception::create( 'Transfers::ItemAlreadyExists', 'An item with a “[_1]” key value of “[_2]” and a type of “[_3]” already exists in the queue.', [ $key, $data->{$key}, $item_type ] );
    }

    $self->_insert_hashref_into( $item_type, $data ) or die "failed to insert: $item_type: $data";

    return $self->_set_state(
        {
            'item_type' => $item_type,
            'item'      => $data->{$key},
            ( length $prerequisite_key ? ( 'prerequisite_key' => $data->{$prerequisite_key} ) : () ),
            'state'    => ( $state || $Whostmgr::Transfers::Session::Constants::QUEUE_STATES{TRANSFER_PENDING} ),
            'pid'      => 0,
            'size'     => $data->{'size'},
            'priority' => ( $data->{'priority'} || $Whostmgr::Transfers::Session::Constants::LOWEST_PRIORITY ),

        }
    );
}

sub _validate_enqueued_data_against_schema {
    my ( $self, $item_type, $data ) = @_;

    my $schema = $self->_get_schema($item_type);

    foreach my $key ( @{ $schema->{'required'} } ) {
        if ( !exists $data->{$key} ) {
            die Cpanel::Exception::create( 'MissingParameter', 'The “[_1]” parameter is required for the “[_2]” module.', [ $key, $item_type ] );
        }
    }

    foreach my $key ( keys %{$data} ) {
        if ( !exists $schema->{'keys'}{$key} ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” parameter is not valid for the “[_2]” module.', [ $key, $item_type ] );
        }
    }

    return 1;
}

sub dequeue_next_item {
    my ( $self, $queue ) = @_;

    my ( $has_item, $has_next_item_in_this_queue, $this_item_type, $data ) = $self->_find_next_item($queue);

    if ($has_item) {
        $self->_prime_next_queue_item( $queue, $this_item_type, $data );
        return $Whostmgr::Transfers::Session::Constants::QUEUE_FETCHED;
    }
    elsif ( $has_next_item_in_this_queue || $self->has_next_item($queue) ) {
        delete $self->{'current_item'};
        return $Whostmgr::Transfers::Session::Constants::QUEUE_BLOCKED;
    }
    else {
        delete $self->{'current_item'};
        $self->set_data( 'queue', $queue, 1 );
        return $Whostmgr::Transfers::Session::Constants::QUEUE_EMPTY;
    }
}

sub item_exists {
    my ( $self, $item_type, $item_key ) = @_;

    return 0 if !$self->table_exists( $self->_unquoted_session_table($item_type) );
    return ( $self->_retrieve_item( $item_type, $item_key ) ) ? 1 : 0;
}

#
# has_next_item used to check to see if there were items that were not marked as completed
# It has since changed to check to see if there are any items that are still in the
# queue that have not yet been picked up to prevent the transfer system children
# from blocking until the entire transfer was finished even though there was never
# going to be anything more for them to do.
#
# At the top of this message, this code was only used in Processor.pm, and it clearly
# expected it to behave with the new behavior all along.
#
sub has_next_item {
    my ( $self, $queue ) = @_;

    if ( my $INPROGRESS_STATE = $Whostmgr::Transfers::Session::Constants::QUEUE_STATES{ $queue . '_INPROGRESS' } ) {
        my $queue_table = $self->_session_table('queue');
        my $row         = $self->session_sql( 'selectrow_arrayref', ["select COUNT(*) from $queue_table where state < $INPROGRESS_STATE LIMIT 1 /* has_next_item $queue */;"] );

        return ( ( $row && ref $row && $row->[0] ) ? 1 : 0 );
    }
    return 0;
}

sub _prime_next_queue_item {
    my ( $self, $queue, $item_type, $data ) = @_;

    my $key  = $self->_get_item_primary_key($item_type);
    my $item = $data->{$key};

    my ( $ok, $err );
    try {
        $ok = $self->_create_current_item(
            {
                'item_type' => $item_type,
                'item'      => $item,
                'queue'     => $queue,
            },
            $data
        );
    }
    catch {
        $err = $_;
    };

    if ( !$ok || $err ) {
        if ($err) {
            warn $err;
        }
        elsif ( !$ok ) {
            warn "Failed to create an object of type “$item_type” for “$item”";
        }

        # We we do not mark it as failed the queue processing never continues
        # because it will keep trying to reprocess the same item
        $self->manually_mark_item_as_failed( $item_type, $item );
        return 0;
    }

    return 1;
}

# This function marks the passed in item as completed.
sub mark_item_as_completed {
    my ( $self, $item_obj ) = @_;

    if ( !$item_obj ) {
        die Cpanel::Exception::create( 'MissingParameter', 'The required parameter “[_1]” is not set.', ['item_obj'] );
    }

    my $item_type = $item_obj->item_type();
    my $item      = $item_obj->item();
    my $queue     = $item_obj->queue();

    $queue =~ tr/a-z/A-Z/;
    my $COMPLETED_STATE = $Whostmgr::Transfers::Session::Constants::QUEUE_STATES{ $Whostmgr::Transfers::Session::Constants::QUEUE_COMPLETED_STATES{$queue} };

    return $self->_set_state( { 'item_type' => $item_type, 'item' => $item, 'state' => $COMPLETED_STATE } );
}

# This function marks a passed in item object as failed.
sub mark_item_as_failed {
    my ( $self, $item_obj ) = @_;

    if ( !$item_obj ) {
        die Cpanel::Exception::create( 'MissingParameter', 'The required parameter “[_1]” is not set.', ['item_obj'] );
    }

    return $self->manually_mark_item_as_failed( $item_obj->item_type(), $item_obj->item() );
}

sub manually_mark_item_as_failed {
    my ( $self, $item_type, $item_key ) = @_;
    my $FAILED_STATE = $Whostmgr::Transfers::Session::Constants::QUEUE_STATES{'FAILED'};

    return $self->_set_state( { 'item_type' => $item_type, 'item' => $item_key, 'state' => $FAILED_STATE } );
}

sub _update_prerequisite_state {
    my ( $self, $prerequisite_key, $prerequisite_state ) = @_;

    # Item might not have a prerequisite key
    return if !length $prerequisite_key;

    if ( !defined $prerequisite_state ) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'prerequisite_state' ] );
    }

    my $queue_table = $self->_session_table('queue');
    my ($numeric_prerequisite_state) = $prerequisite_state =~ m{([0-9]+)};

    return $self->session_do( [ "UPDATE $queue_table SET prerequisite_state=? WHERE prerequisite_key=? /* _update_prerequisite_state */;", undef, $numeric_prerequisite_state, $prerequisite_key ] );
}

sub get_item_and_state_by_assigned_pid {
    my ( $self, $assigned_pid ) = @_;

    if ( !defined $assigned_pid ) {
        die Cpanel::Exception::create( 'MissingParameter', 'The required parameter “[_1]” is not set.', ['$assigned_pid'] );
    }

    my $queue_table = $self->_session_table('queue');
    my $row         = $self->session_sql( 'selectrow_arrayref', [ "select type, keyname, state, size from $queue_table where pid=? LIMIT 1;", undef, $assigned_pid ] );
    return if !$row || !ref $row;

    my ( $item_type_id, $item_key_value, $state, $size ) = @{$row};

    my $queue     = $self->get_item_queue_from_state($state);
    my $item_type = $self->_itemtype_id_to_name($item_type_id);
    my $key       = $self->_get_item_primary_key($item_type);

    return (
        $self->_create_current_item(
            {
                'item_type' => $item_type,
                'item'      => $item_key_value,
                'queue'     => $queue,
            },
            {
                $key   => $item_key_value,    # AKA user=>bob
                'size' => $size
            }
        ),
        $state
    );
}

sub _create_current_item {
    my ( $self, $item_info, $input ) = @_;

    my $item_type   = $item_info->{'item_type'};
    my $object_type = "Whostmgr::Transfers::Session::Items::$item_type";
    Cpanel::LoadModule::load_perl_module($object_type);

    return (
        $self->{'current_item'} = "$object_type"->new(
            'queue'       => $item_info->{'queue'},
            'item_type'   => $item_type,
            'item'        => $item_info->{'item'},
            'input'       => $input,
            'size'        => $input->{'size'},
            'session_obj' => $self,
        )->weaken_session()
    );
}

sub get_item_queue_from_state {
    my ( $self, $state ) = @_;

    if ( !defined $state ) {
        die Cpanel::Exception::create( 'MissingParameter', 'The required parameter “[_1]” is not set.', ['state'] );
    }

    return $state < $Whostmgr::Transfers::Session::Constants::QUEUE_STATES{'RESTORE_PENDING'} ? 'TRANSFER' : 'RESTORE';
}

sub update_hashref_key {
    my ( $self, $item_type, $item, $key, $value ) = @_;

    my $quoted_table = $self->_session_table($item_type);
    my $find_key     = $self->_get_item_primary_key($item_type);
    my $quoted_key   = $self->quote_identifier($key);

    return $self->session_do( [ "UPDATE $quoted_table SET $quoted_key=? WHERE $find_key=?;", undef, $value, $item ] );

}

sub get_data {
    my ( $self, $section, $key ) = @_;

    my $session_table = $self->_session_table('session');

    my $data;
    if ($key) {
        my $row = $self->session_sql( 'selectrow_arrayref', [ "SELECT keyvalue from $session_table where section=? and keyname=?", undef, $section, $key ] );
        if ( ref $row ) {
            $data = $key =~ m{$PASSWORD_MATCH}i ? $self->_decode_data( $row->[0] ) : $row->[0];
        }

    }
    elsif ( ref $section ) {
        my $sections = join( ',', map { $self->quote($_) } @{$section} );
        my $temp     = $self->session_sql( 'selectall_arrayref', [ "SELECT section,keyname,keyvalue from $session_table where section IN ($sections);", { 'Slice' => {} } ] );
        if ( ref $temp ) {
            $data = {};
            foreach my $row ( @{$temp} ) {
                $data->{ $row->{'section'} }{ $row->{'keyname'} } = $row->{'keyname'} =~ m{$PASSWORD_MATCH}i ? $self->_decode_data( $row->{'keyvalue'} ) : $row->{'keyvalue'};
            }
        }
    }
    else {
        $data = $self->session_sql( 'selectall_hashref', [ "SELECT keyname,keyvalue from $session_table where section=?", 'keyname', {}, $section ] );
        if ( ref $data ) {
            foreach my $key ( keys %{$data} ) {
                $data->{$key} = $key =~ m{$PASSWORD_MATCH}i ? $self->_decode_data( $data->{$key}{'keyvalue'} ) : $data->{$key}{'keyvalue'};
            }
        }
    }

    return $data;
}

sub set_data {
    my ( $self, $arg1, $arg2, $arg3 ) = @_;

    my $data;
    if ( ref $arg1 ) {
        $data = $arg1;
    }
    elsif ( ref $arg2 ) {
        $data = { $arg1 => $arg2 };
    }
    else {
        $data = { $arg1 => { $arg2 => $arg3 } };
    }

    my $session_table = $self->_session_table('session');
    my @ret;

    foreach my $section ( keys %{$data} ) {
        my $quoted_section = $self->quote($section);
        my @VALUES;

        foreach my $key ( keys %{ $data->{$section} } ) {
            my $quoted_key   = $self->quote($key);
            my $value        = $data->{$section}->{$key} || 0;
            my $safe_value   = $key =~ m{$PASSWORD_MATCH}i ? $self->_encode_data($value) : $value;
            my $quoted_value = $self->quote($safe_value);

            push @VALUES, " ($quoted_section, $quoted_key, $quoted_value) ";
        }

        @ret = $self->session_do( "INSERT OR REPLACE INTO $session_table (section,keyname,keyvalue) VALUES " . join( ',', @VALUES ) . ";" );

        if ( !$ret[0] ) { return @ret; }
    }
    return @ret;

}

sub disconnect {
    my ($self) = @_;

    delete $self->{'current_item'};

    if ( $INC{'Whostmgr/Remote.pm'} ) {
        Whostmgr::Remote::close_all_cached_connections();
    }

    return $self->SUPER::disconnect();
}

sub output_message {
    my ( $self, $type, $data ) = @_;

    if ( ref $data ) {
        $data->{'time'} ||= time();
    }
    if ( !$self->{'output_obj'} ) {
        _confess("The “output_obj” property is missing.");
    }

    return $self->{'output_obj'}->message( $type, $data );
}

#### LOOKUPS

sub id {
    my ($self) = @_;

    return $self->{'_session_id'} || die Cpanel::Exception::create( 'AttributeNotSet', 'The attribute “[_1]” has not been set.', ['session_id'] );
}

sub initiator {
    my ($self) = @_;

    return $self->{'initiator'} || $self->SUPER::initiator( $self->id() );
}

sub creator {
    my ($self) = @_;

    return ( $self->{'creator'} ||= $self->SUPER::creator( $self->id() ) );
}

sub ssh_ip {
    my ($self) = @_;
    return $self->get_data( 'remote', 'sship' );
}

sub ssh_host {
    my ($self) = @_;
    return $self->get_data( 'remote', 'sshhost' );
}

sub ssh_port {
    my ($self) = @_;
    return $self->get_data( 'remote', 'sshport' );
}

sub can_stream {
    my ($self) = @_;
    return $self->get_data( 'remote', 'can_stream' );
}

sub can_rsync {
    my ($self) = @_;
    return $self->get_data( 'remote', 'can_rsync' );
}

sub authinfo {
    my ($self) = @_;
    return $self->get_data('authinfo');
}

sub queueinfo {
    my ($self) = @_;
    return $self->get_data('queue');
}

sub sessioninfo {
    my ($self) = @_;
    return $self->get_data('session');
}

sub remoteinfo {
    my ($self) = @_;
    return $self->get_data('remote');
}

sub options {
    my ($self) = @_;
    return $self->get_data('options');
}

sub authmethod {
    my ($self) = @_;
    return $self->get_data( 'authinfo', 'authmethod' );
}

sub servtype {
    my ($self) = @_;
    return $self->get_data( 'remote', 'type' );
}

sub cpversion {
    my ($self) = @_;
    return $self->get_data( 'remote', 'cpversion' );
}

sub scriptdir {
    my ($self) = @_;
    return $self->get_data( 'session', 'scriptdir' );
}

#### PRIVATE
sub new {
    my ( $class, %OPTS ) = @_;
    my $session_id = $OPTS{'id'};

    if ( $session_id && $session_id !~ m{^[0-9A-Za-z_]+$} ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The session ID “[_1]” may only contain alphanumeric characters and underscores.', [$session_id] );
    }
    my $self = bless $class->SUPER::new(%OPTS), $class;

    if ( !$session_id ) {
        if ( $OPTS{'create'} ) {
            $session_id = $self->_generate_session_id( $OPTS{'session_id_template'}, $OPTS{'initiator'} );
        }
        else {
            die Cpanel::Exception::create( 'MissingParameter', 'The [list_or_quoted,_1] parameter is required to create a session object.', [ [ 'id', 'create' ] ] );
        }
    }

    if ( !$OPTS{'create'} && !$self->_session_exists($session_id) ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The session ID “[_1]” does not exist.', [$session_id] );
    }

    $self->{'initiator'} = $OPTS{'initiator'} if $OPTS{'initiator'};
    $self->{'creator'}   = $OPTS{'creator'}   if $OPTS{'creator'};

    $self->{'_session_id'} = $session_id;

    #This will ensure that the appropriate directory exists.
    $self->logs();

    if ( !$self->_set_session_id($session_id) ) {
        die Cpanel::Exception::create( 'Transfers::UnableToSetSessionID', 'The system is unable to set session ID “[_1]” for this object.', [$session_id] );
    }

    return $self;
}

sub _generate_session_id {
    my ( $self, $template, $initiator ) = @_;

    my $max_template = substr( $template || '', 0, 15 ) . substr( $initiator || '', 0, 5 ) . Cpanel::Time::time2condensedtime();

    $max_template =~ s{[^0-9A-Za-z_]}{}g if length $max_template;

    my $rand = Cpanel::Rand::Get::getranddata( 36 - length $max_template, [ 0 .. 9, 'A' .. 'Z', 'a' .. 'z' ] );

    return $max_template . $rand;
}

sub _empty_queue {
    my ( $self, $queue ) = @_;

    my $quoted_table = $self->_session_table($queue);

    $self->session_do("DELETE FROM $quoted_table");

    my $numeric_item_type = $self->_itemtype_name_to_id($queue);

    $self->session_do("DELETE FROM queue where type=$numeric_item_type;");

    return 1;
}

sub _delete_session {
    my ($self) = @_;

    return $self->SUPER::_delete_session( $self->id() );
}

sub _insert_quoted_values_hashref_into {
    my ( $self, $table, $hashref ) = @_;

    my $quoted_table = $self->_session_table($table);

    my ( @KEYS, @VALUES );

    foreach my $key ( keys %{$hashref} ) {
        push @KEYS,   $self->quote_identifier($key);
        push @VALUES, $hashref->{$key};
    }

    my $cols = "(" . join( ',', @KEYS ) . ")";
    my $vals = "(" . join( ',', @VALUES ) . ")";

    return $self->session_do("INSERT INTO $quoted_table $cols VALUES$vals;");
}

sub _insert_hashref_into {
    my ( $self, $table, $hashref ) = @_;

    my $quoted_table = $self->_session_table($table);

    my ( @KEYS, @VALUES );

    foreach my $key ( keys %{$hashref} ) {
        push @KEYS,   $self->quote_identifier($key);
        push @VALUES, $self->quote( $hashref->{$key} );
    }

    my $cols = "(" . join( ',', @KEYS ) . ")";
    my $vals = "(" . join( ',', @VALUES ) . ")";

    return $self->session_do("INSERT INTO $quoted_table $cols VALUES$vals;");
}

sub _session_table {
    my ( $self, $table ) = @_;

    return $self->quote_identifier( $self->_unquoted_session_table($table) );
}

sub _unquoted_session_table {
    my ( $self, $table ) = @_;
    return $table;
}

sub _set_state {
    my ( $self, $input ) = @_;

    _confess("_set_state requires a hashref input") if !ref $input;

    my $item_type = $input->{'item_type'};
    my $item      = $input->{'item'};
    _confess("Missing item") if !$item;
    my $quoted_item       = $self->quote($item);
    my $numeric_item_type = $self->_itemtype_name_to_id($item_type);

    my @UPDATES;
    my $insert          = 0;
    my $state           = $input->{'state'};
    my ($numeric_state) = ( $state ||= 0 ) =~ m{([0-9]+)};
    push @UPDATES, [ "state" => $numeric_state ];

    my $priority = $input->{'priority'};
    my ($numeric_priority) = ( $priority ||= $Whostmgr::Transfers::Session::Constants::LOWEST_PRIORITY ) =~ m{([0-9]+)};
    push @UPDATES, [ "priority" => $numeric_priority ];

    my $pid = $input->{'pid'};
    my ($numeric_pid) = ( $pid ||= 0 ) =~ m{([0-9]+)};    # pid can be undef if we do not want to update it
    push @UPDATES, [ "pid" => $numeric_pid ];

    if ( exists $input->{'size'} ) {
        $insert = 1;
        my $size = $input->{'size'};
        my ($numeric_size) = ( $size ||= 1 ) =~ m{([0-9]+)};    # no size?, default to 1 as it MUST have some size
        push @UPDATES, [ "size" => $numeric_size ];
    }

    if ( exists $input->{'prerequisite_key'} ) {
        my $prerequisite_key        = $input->{'prerequisite_key'};
        my $quoted_prerequisite_key = length $prerequisite_key ? $self->quote($prerequisite_key) : 'NULL';
        push @UPDATES, [ 'prerequisite_key' => $quoted_prerequisite_key ];
        my $numeric_prerequisite_state = length $prerequisite_key ? 0 : $Whostmgr::Transfers::Session::Constants::QUEUE_STATES{'COMPLETED'};
        push @UPDATES, [ 'prerequisite_state' => $numeric_prerequisite_state ];
    }
    elsif ($insert) {
        push @UPDATES, [ 'prerequisite_state' => $Whostmgr::Transfers::Session::Constants::QUEUE_STATES{'COMPLETED'} ];
    }

    my $ret;

    if ($insert) {
        my $hashref = { map { @{$_} } @UPDATES };
        $hashref->{'type'}      = $numeric_item_type;
        $hashref->{'keyname'}   = $quoted_item;
        $hashref->{'randindex'} = $self->quote( Cpanel::Rand::Get::getranddata(32) );
        $ret                    = $self->_insert_quoted_values_hashref_into( 'queue', $hashref );
    }
    else {
        my $queue_table = $self->_session_table('queue');

        # Note: on update, we only change the pid, state.  The size, type, prerequisite_key, and item are FIXED forever once inserted.
        # The column prerequisite_state will use the default of 0 and be updated by _update_prerequisite_state

        my $sql = "UPDATE $queue_table SET " . join( ',', map { $_->[0] . '=' . $_->[1] } @UPDATES ) . " WHERE type=$numeric_item_type and keyname=$quoted_item;";
        $ret = $self->session_do($sql);

    }

    if ( $ret && $state ) {
        $self->_update_prerequisite_state( $item, $state );
    }

    return $ret;
}

sub _set_session_id {
    my ( $self, $session_id ) = @_;

    if ( !$self->session_id_exists($session_id) ) {
        $self->_create_new_session($session_id);
    }
    else {
        $self->get_session_connection($session_id);
    }

    return $self->_populate_session_encoder_secret();
}

sub _find_next_item {
    my ( $self, $queue ) = @_;

    my $session_id       = $self->id();
    my $queue_table      = $self->_session_table('queue');
    my $PENDING_STATE    = $Whostmgr::Transfers::Session::Constants::QUEUE_STATES{ $queue . '_PENDING' };
    my $INPROGRESS_STATE = $Whostmgr::Transfers::Session::Constants::QUEUE_STATES{ $queue . '_INPROGRESS' };

    my ( $type_to_process, $has_pending_of_same_type, $has_any_pending ) = $self->_find_item_type_to_process($queue);    # If any other thread is currently working on a type
                                                                                                                         # it will be returned here
    return ( 0, $has_any_pending ) if !$has_pending_of_same_type;

    my $random_key        = Cpanel::Rand::Get::getranddata(16);
    my $quoted_random_key = $self->quote($random_key);

    # Mark the item that it is for us
    # We cannot use a SET @ variable here because
    # we need to handle the case where our mysql connection
    # gets dropped between the update and the select below
    my $got_item = $self->session_do(
        [
            "UPDATE $queue_table
            SET state=$INPROGRESS_STATE,pid=$$,randkey=$quoted_random_key where randindex IN (
                SELECT randindex from $queue_table where
                        state=$PENDING_STATE and
                        pid=0 and type=$type_to_process and
                        prerequisite_state > $INPROGRESS_STATE
                        ORDER BY type,priority,keyname ASC LIMIT 1
            )
            /* _find_next_item */;
          "
        ]
    );

    # Its possible that it got picked up by someone else in the process and there are no
    # rows left
    return ( 0, $has_pending_of_same_type ) if !$got_item || $got_item != 1;    # Note: must check for 1 as it could be 0E0

    # Now pickup the row we marked for processing
    my $row = $self->session_sql( 'selectrow_hashref', [ "select * from $queue_table where randkey=? /* _find_next_item */;", undef, $random_key ] );

    return ( 0, $has_pending_of_same_type ), if !$row;
    return ( 1, $has_pending_of_same_type, $self->_retrieve_item( $self->_itemtype_id_to_name( $row->{'type'} ), $row->{'keyname'} ) );
}

sub fetch_largest_items {
    my ( $self, $count ) = @_;

    my $queue_table = $self->_session_table('queue');

    return $self->session_sql( 'selectall_arrayref', [ "select keyname as item,size from $queue_table ORDER by size DESC LIMIT ? /* fetch_largest_items */;", { Slice => {} }, int($count) ] );
}

sub _find_item_type_to_process {

    # We cannot start on accounts until packages and featurelists are done
    # So we must determine what type is currently in progress
    # so we restrict picking up new items to that type in _find_next_item

    my ( $self, $queue ) = @_;

    my $PENDING_STATE    = $Whostmgr::Transfers::Session::Constants::QUEUE_STATES{ $queue . '_PENDING' };
    my $INPROGRESS_STATE = $Whostmgr::Transfers::Session::Constants::QUEUE_STATES{ $queue . '_INPROGRESS' };

    my $queue_table = $self->_session_table('queue');
    my $data        = $self->session_sql( 'selectall_arrayref', [ "select state,pid,type from $queue_table where state IN ($INPROGRESS_STATE, $PENDING_STATE) /* _find_item_to_process */;", { Slice => {} } ] );

    my ( $type_to_process, $has_pending_of_same_type, $has_any_pending );

    if ( $data && @{$data} ) {
        foreach my $row ( sort { $b->{'state'} <=> $a->{'state'} || $a->{'type'} <=> $b->{'type'} } @{$data} ) {

            # IN PROGRESS
            if ( !$type_to_process && $row->{'pid'} && $self->transfer_pid_is_running( $row->{'pid'} ) ) {
                $type_to_process = $row->{'type'};
            }

            # PENDING
            elsif ( $row->{'state'} == $PENDING_STATE ) {
                $type_to_process ||= $row->{'type'};

                if ( $type_to_process eq $row->{'type'} ) {
                    $has_any_pending = $has_pending_of_same_type = 1;
                }
                else {
                    $has_any_pending = 1;
                }
                last;
            }
        }
    }

    return ( $type_to_process, $has_pending_of_same_type, $has_any_pending );
}

sub _itemtype_id_to_name {
    my ( $self, $id ) = @_;

    return $Whostmgr::Transfers::Session::Config::ITEMTYPE_NAMES{$id} || die Cpanel::Exception::create( 'RecordNotFound', 'The system could not find an item with [asis,ID] “[_1]”.', [$id] );
}

sub _itemtype_name_to_id {
    my ( $self, $name ) = @_;

    return $ITEMTYPE_IDS{$name} || die Cpanel::Exception::create( 'RecordNotFound', 'The system could not find an item with [asis,NAME] “[_1]”.', [$name] );
}

sub _get_current_item {
    my ($self) = @_;

    return $self->{'current_item'} || die Cpanel::Exception::create( 'RecordNotFound', 'There is no current record.' );
}

sub _has_current_item {
    my ($self) = @_;

    return defined $self->{'current_item'};
}

sub _retrieve_item {
    my ( $self, $item_type, $keyname ) = @_;

    my $quoted_value     = $self->quote($keyname);
    my $quoted_item_type = $self->_session_table($item_type);

    my $key = $self->_get_item_primary_key($item_type);

    my $row = $self->session_sql( "selectrow_hashref", ["select * from $quoted_item_type where $key=$quoted_value;"] );

    return if !$row;

    return ( $item_type, $row );

}

sub _locale {
    eval 'require Cpanel::Locale' if !$INC{'Cpanel/Locale.pm'};
    return $locale ||= Cpanel::Locale->get_handle();
}

sub logs {
    my ($self) = @_;
    return ( $self->{'log_obj'} ||= Whostmgr::Transfers::Session::Logs->new( 'id' => $self->id() ) );
}

sub _populate_session_encoder_secret {
    my ($self) = @_;

    #This will ensure that the appropriate directory exists.
    $self->logs();

    my $session_id = $self->id();

    my $session_secret_file = $Whostmgr::Transfers::Session::Config::SESSION_DIR . '/' . $session_id . '/session_encoder_key';

    my $secret;
    if ( -s $session_secret_file ) {
        $secret = Cpanel::LoadFile::load($session_secret_file);
    }

    if ( !$secret ) {
        $secret = Cpanel::Rand::Get::getranddata(255);
        Cpanel::FileUtils::Write::overwrite_no_exceptions( $session_secret_file, $secret, 0600 ) || die Cpanel::Exception::create( 'IO::FileWriteError', [ path => $session_secret_file, error => $! ] );
    }

    $self->{'_session_encoder'} = Cpanel::Session::Encoder->new( 'secret' => $secret );

    return 1;
}

sub _encode_data {
    my ( $self, $data ) = @_;

    return $self->{'_session_encoder'}->encode_data($data);
}

sub _decode_data {
    my ( $self, $data ) = @_;

    return $self->{'_session_encoder'}->decode_data($data);
}

sub _get_item_primary_key {
    my ( $self, $this_item_type ) = @_;

    return $self->_get_schema($this_item_type)->{'primary'}->[0];
}

sub _get_item_prerequisite_key {
    my ( $self, $this_item_type ) = @_;

    return $self->_get_schema($this_item_type)->{'prerequisite'};
}

sub _generate_schema {
    my ($self) = @_;

    my %tables = (
        'queue' => {

            'keys' => {
                'type'               => { 'def' => 'bigint(20) NOT NULL' },
                'keyname'            => { 'def' => 'char(255) NOT NULL' },
                'priority'           => { 'def' => 'int(1) DEFAULT 255' },
                'prerequisite_key'   => { 'def' => 'char(255) DEFAULT NULL' },
                'prerequisite_state' => { 'def' => 'bigint(20) DEFAULT 0' },
                'size'               => { 'def' => 'BIGINT UNSIGNED DEFAULT 1' },
                'state'              => { 'def' => 'bigint(20) DEFAULT 0' },
                'pid'                => { 'def' => 'bigint(20) DEFAULT 0' },
                'randindex'          => { 'def' => 'char(64)' },
                'randkey'            => { 'def' => 'char(64)' },
            },
            'primary' => [ 'type', 'keyname' ]
        },
        'session' => {
            'keys' => {
                'section'  => { 'def' => "char (166) NOT NULL DEFAULT ''" },
                'keyname'  => { 'def' => "char (166) NOT NULL DEFAULT ''" },
                'keyvalue' => { 'def' => 'mediumtext' },
            },
            'primary' => [ 'section', 'keyname' ],
        },
    );

    my @schema           = $self->_generate_schema_for_tables( \%tables );
    my $queue_table_name = $self->_session_table('queue');

    push @schema, "CREATE INDEX randindex_index ON $queue_table_name (randindex);";
    push @schema, "CREATE INDEX randkey_index ON $queue_table_name (randkey);";
    push @schema, "CREATE INDEX state_index ON $queue_table_name (state);";
    return @schema;
}

sub _generate_schema_for_tables {
    my ( $self, $tables_ref ) = @_;

    my @schema;
    foreach my $table ( keys %{$tables_ref} ) {
        my $table_name      = $self->_session_table($table);
        my $table_structure = join(
            ",\n",
            ( map { $self->quote_identifier($_) . ' ' . $tables_ref->{$table}{'keys'}{$_}{'def'} } keys %{ $tables_ref->{$table}{'keys'} } ),
            ( 'PRIMARY KEY (' . join( ',', map { $self->quote_identifier($_) } @{ $tables_ref->{$table}{'primary'} } ) . ')' )
        );
        push @schema, "DROP TABLE IF EXISTS $table_name;";
        push @schema, "CREATE TABLE $table_name ($table_structure);";
    }

    return @schema;
}

sub _get_schema {
    my ( $self, $this_item_type ) = @_;

    my $object_type = "Whostmgr::Transfers::Session::Items::Schema::$this_item_type";
    Cpanel::LoadModule::load_perl_module($object_type);

    return "$object_type"->schema();
}

sub _create_new_session {
    my ( $self, $session_id ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', 'The parameter “[_1]” is required.', ['session_id'] ) if !length $session_id;

    my $initiator = $self->{'initiator'};
    my $creator   = $self->{'creator'} || 'root';

    my $target_host = Cpanel::Sys::Hostname::gethostname();

    my $quoted_session_id  = $self->quote($session_id);
    my $quoted_target_host = $self->quote($target_host);
    my $quoted_initiator   = $self->quote($initiator);
    my $quoted_creator     = $self->quote($creator);
    my $quoted_version     = $self->quote($Whostmgr::Transfers::Session::Config::VERSION);

    my @all_schema = $self->_generate_schema();

    #
    # In v58+ we have two databases per session
    #
    #    /var/cpanel/transfer_sessions/whmxfer.sqlite which has a list of all session
    #    and a session specific datbase
    #    /var/cpanel/transfer_sessions/$session_id/db.sqlite
    #
    # If we do not put the entry in the session db (whmxfer.sqlite)
    # first then get_session_connection will fail for resellers
    # because they will not have their username in the creator entry
    # telling get_session_connection that they are allowed access
    #
    $self->master_do("INSERT INTO sessions (sessionid,version,creator,initiator,target_host,starttime) VALUES($quoted_session_id,$quoted_version,$quoted_creator,$quoted_initiator,$quoted_target_host,datetime());") || die Cpanel::Exception::create( 'Database::TableInsertionFailed', 'The system failed to insert a session entry for “[_1]”.', [$session_id] );

    $self->get_session_connection($session_id);

    foreach my $schema (@all_schema) {
        $self->session_do($schema) || die Cpanel::Exception::create( 'Database::TableCreationFailed', 'The system was unable to create the table schema for session “[_1]”.', [$session_id] );
    }

    return 1;
}

sub exec_with_output_directed_to_fh {
    my ( $self, $log_fhs, $coderef ) = @_;

    my $original_stdout_fh;
    my $original_stderr_fh;

    # 0 = STDOUT
    # 1 = STDERR
    $log_fhs = [ $log_fhs, $log_fhs ] if ref $log_fhs ne 'ARRAY';

    open( $original_stdout_fh, '>&STDOUT' )                      || die "dup(STDOUT) failed: $!";
    open( $original_stderr_fh, '>&STDERR' )                      || die "dup(STDERR) failed: $!";
    open( STDOUT,              '>&=' . fileno( $log_fhs->[0] ) ) || die "STDOUT redefine failed: $!";    ##no critic qw(ProhibitTwoArgOpen)
    open( STDERR,              '>&=' . fileno( $log_fhs->[1] ) ) || die "STDERR redefine failed: $!";    ##no critic qw(ProhibitTwoArgOpen)

    STDERR->autoflush(1);
    STDOUT->autoflush(1);

    $self->{'output_obj'} ||= Cpanel::Output->new();

    my $out_fh = IO::Handle->new();
    tie *$out_fh, 'Cpanel::WrapOutputFH', ( 'output_obj' => $self->{'output_obj'} );
    my $orig_fh = select($out_fh);                                                                       ##no critic qw(ProhibitOneArgSelect)

    local $@;
    my ( @results, $error_trap );
    try {
        @results = $coderef->();
    }
    catch {
        $error_trap = $_;
    };

    untie *$out_fh;
    select($orig_fh);                                                                                    ##no critic qw(ProhibitOneArgSelect)

    open( STDOUT, '>&=' . fileno($original_stdout_fh) ) || die "STDOUT redefine failed: $!";             ##no critic qw(ProhibitTwoArgOpen)
    open( STDERR, '>&=' . fileno($original_stderr_fh) ) || die "STDERR redefine failed: $!";             ##no critic qw(ProhibitTwoArgOpen)

    return ( \@results, $error_trap );

}

sub _signal_transfer_processes_and_children_to_abort {
    my ( $self, @pids_to_kill ) = @_;
    require Cpanel::PsParser;
    require Cpanel::Kill;
    require Cpanel::Debug;
    Cpanel::Debug::log_info("Transfer Abort requested: Signaling processes “@pids_to_kill” to abort.");

    # We want to term rsync, tar, and whmxfer_stream as well
    # The transfer session will handle SIGTERM and know not to
    # respawn the children.  It is important that we signal the
    # children AFTER the parents or they will get respawned.

    my @child_pids_to_kill = Cpanel::PsParser::get_child_pids(@pids_to_kill);

    kill( 'TERM', @pids_to_kill );

    for ( 1 .. 3 ) {
        sleep(1);
        Cpanel::Debug::log_info("Transfer Abort requested: Terminating child process “@child_pids_to_kill”.");
        Cpanel::Kill::safekill_multipid( \@child_pids_to_kill );

        # If new children have been spawned because the transfer
        # parent process did not get enough time to process the signal
        # we need to check again in case its still runing
        @child_pids_to_kill = Cpanel::PsParser::get_child_pids(@pids_to_kill);

        # Give the parent enough time to handle the signal
        last if !@child_pids_to_kill;    # all dead
        sleep(4);
    }

    return 1;
}

sub _confess {
    require Cpanel::Carp;
    die Cpanel::Carp::safe_longmess(@_);
}

1;
