package Whostmgr::Transfers::Session::Processor;

# cpanel - Whostmgr/Transfers/Session/Processor.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use parent 'Cpanel::Destruct::DestroyDetector';

use IO::Handle ();

use Try::Tiny;
use Cpanel::Carp                  ();
use Whostmgr::Transfers::State    ();
use Cpanel::Server::Type          ();
use Cpanel::TimeHiRes             ();
use Cpanel::Sys::Setsid::Fast     ();
use Cpanel::Signals               ();
use Cpanel::ChildErrorStringifier ();
use Cpanel::Exception             ();
use Cpanel::ForkAsync             ();
use Cpanel::Output                ();
use Cpanel::DiskCheck             ();
use Cpanel::Filesys::Home         ();
use Cpanel::Logger                ();
use Cpanel::Rusage                ();
use Cpanel::Timezones             ();
use Cpanel::Debug                 ();
use Cpanel::Hooks                 ();

use Whostmgr::Remote::State                 ();
use Whostmgr::Transfers::Session            ();
use Whostmgr::Transfers::Session::Constants ();
use Whostmgr::UI                            ();

use Cpanel::PublicSuffix ();    # PPI USE OK -- laod before cPanel::PublicAPI so we provide our PublicSuffix module to HTTP::CookieJar

use cPanel::PublicAPI ();

use Whostmgr::Transfers::SessionBase ();

use Whostmgr::Transfers::Session::Items::LegacyAccountBackup   ();    # PPI USE OK - perlcc preload
use Whostmgr::Transfers::Session::Items::AccountRemoteRoot     ();    # PPI USE OK - perlcc preload
use Whostmgr::Transfers::Session::Items::FeatureListRemoteRoot ();    # PPI USE OK - perlcc preload
use Whostmgr::Transfers::Session::Items::PackageRemoteRoot     ();    # PPI USE OK - perlcc preload

#If the restoration process exceeds 512 MiB, then we want the processor
#child to exit so a new restore child can be spawned and take over
#after the item the restore child is processing completes.  This avoids
#a problem where memory leaks build up and we end up with a cascading
#failure.

#
# See Whostmgr::Transfers::Session::Setup::AVG_MEMORY_USAGE_BY_THREAD_TYPE_MEGS
#

use constant _MAX_ALLOWED_RSS_KIB => 512 * 1_024;

use Errno qw[EINTR];

# THIS MODULE IS NOW UNSHIPPED! PLEASE DO NOT SHIP THIS MODULE!

#
# This module's purpose is to consume transfer and restore items in a single transfer/restore session.
# It does so by creating multiple child processes that are setup to consume items from either the transfer
# or restore queues. These child processes are termed "threads" for convenience in communication, but they are
# separate processes.
#

our $TIME_BETWEEN_CHILD_CHECKS = 0.25;

our $MAX_THREADS = 9;

my $logger;
my $locale;

sub new {
    my ( $class, $transfer_session_id, $opts ) = @_;

    if ( !length $transfer_session_id ) {
        die Cpanel::Exception::create( 'MissingParameter', 'The required parameter “[_1]” is not set.', ['transfer_session_id'] );
    }

    my $dbh = $opts && ref $opts ? $opts->{'dbh'} : undef;

    # Case 176937 restorepkg --force should ignore disk space checks
    my $ignore_disk_space = 0;
    if ( $opts && ref $opts && exists $opts->{'ignore_disk_space'} ) {
        $ignore_disk_space = $opts->{'ignore_disk_space'};
    }

    # “Reconstitute” the session object based on the transfer session ID.
    my $session_obj = Whostmgr::Transfers::Session->new(
        'id' => $transfer_session_id,
        $dbh ? ( 'dbh' => $dbh ) : (),
        'ignore_disk_space' => $ignore_disk_space,
    );

    my $self         = {};
    my $session_info = $session_obj->sessioninfo();

    $self->{'ignore_disk_space'} = $ignore_disk_space;
    $self->{'session_obj'}       = $session_obj;
    $self->{'TRANSFER_threads'}  = $session_info->{'transfer_threads'} || 1;
    $self->{'RESTORE_threads'}   = $session_info->{'restore_threads'}  || 1;
    $self->{'output_obj'}        = Cpanel::Output->new();
    $self->{'_children'}         = {};

    $session_obj->set_output_obj( $self->{'output_obj'} );

    bless $self, $class;

    $self->_reduce_thread_counts_to_maximum($MAX_THREADS);

    $self->_reduce_thread_counts_if_low_disk_space() if !$ignore_disk_space;

    return $self;
}

sub _reduce_thread_counts_to_maximum {
    my ( $self, $max ) = @_;

    # solo are restricted to a single thread
    $max = 1 if Cpanel::Server::Type::get_max_users() == 1;

    foreach my $queue (@Whostmgr::Transfers::Session::Constants::QUEUES) {
        my $thread_type = $queue . '_threads';
        if ( $self->{$thread_type} < 1 ) {
            $self->{$thread_type} = 1;
        }
        elsif ( $self->{$thread_type} > $max ) {
            $self->{$thread_type} = $max;
        }
    }

    return 1;
}

sub logs {
    my ($self) = @_;
    return $self->session()->logs();
}

# Returns a Whostmgr::Transfers::Session.
sub session {
    my ($self) = @_;

    return $self->{'session_obj'};
}

# Returns a Whostmgr::Transfers::Session::Item.
sub current_item {
    my ($self) = @_;

    return $self->session()->{'current_item'};
}

# This function is the parent process that will create the
# child "threads"
sub start {
    my ($self) = @_;

    local $Whostmgr::UI::method          = 'hide';
    local $Whostmgr::Remote::State::HTML = 0;
    local $ENV{'TZ'}                     = Cpanel::Timezones::calculate_TZ_env();

    my $session_obj = $self->session();
    my $session_id  = $session_obj->id();
    my $resume      = 0;

    if ( $session_obj->is_running() ) {
        return $session_obj->get_pid();
    }
    elsif ( $session_obj->is_aborted() ) {
        die Cpanel::Exception::create( 'Transfers::SessionAborted', 'The processor failed to start because the session “[_1]” has been aborted.', [$session_id] );
    }
    elsif ( $session_obj->is_paused() ) {
        if ( $session_obj->unpause() ) {
            $resume = 1;
        }
        else {
            # could not unpause
            die Cpanel::Exception::create( 'Transfers::SessionPausing', 'The processor failed to start because the session “[_1]” is pausing.', [$session_id] );
        }
    }
    else {
        Cpanel::Hooks::hook(
            {
                'category' => 'Whostmgr',
                'event'    => 'Transfers::Session',
                'stage'    => 'pre',
            },
            { 'session_details' => $session_obj->get_session_details() }
        );
        $session_obj->start();
    }

    $session_obj->disconnect();

    my $session_pid = Cpanel::ForkAsync::do_in_child(
        sub {
            $self->_process_child_with_output_redirection( $session_obj, $resume, $session_id );
        }
    );
    $session_obj->reconnect();
    $session_obj->set_pid($session_pid);

    return $session_pid;
}

# This functions sets up the output redirection and initializes the logs for the session.
sub _process_child_with_output_redirection {
    my ( $self, $session_obj, $resume, $session_id ) = @_;

    die "_process_child_with_output_redirection requires a session_id" if !length $session_id;

    # CloseFDs breaks sqlite so we now do this in
    # Whostmgr::Transfers::Session::Start so we are always
    # running with a clean set of fds
    Cpanel::Sys::Setsid::Fast::fast_setsid();

    my $error_log_fh = $self->logs()->open_master_error_log_file();
    open( STDERR, '>&=' . fileno($error_log_fh) ) || die "Failed to dup STDERR";    ##no critic qw(ProhibitTwoArgOpen)

    no warnings 'once';
    local $Cpanel::Carp::OUTPUT_FORMAT = 'text';
    local $Cpanel::Carp::SHOW_TRACE    = 1;

    local $SIG{'TERM'} = \&Cpanel::Signals::set_TERM;
    local $SIG{'USR1'} = \&Cpanel::Signals::set_USR1;

    my $log_fh = $self->logs()->open_master_log_file();
    open( STDIN, '<', '/dev/null' ) || die "Failed to dup STDIN";
    open( STDOUT, '>&=' . fileno($log_fh) ) || die "Failed to dup STDOUT";          ##no critic qw(ProhibitTwoArgOpen)

    $0 = "transfer_session - $session_id - MASTER";
    $self->_process_child( $session_obj, $resume );

    $session_obj->disconnect();                                                     # prevent error on global destruct

    exit(0);
}

# This function creates the processing "threads"
sub _process_child {
    my ( $self, $session_obj, $resume ) = @_;

    die "BUG: The session object must not be connected before fork()" if $session_obj->connected();
    $session_obj->reconnect();                                                      # need to reconnect after fork();
    $session_obj->set_pid($$);
    my $session_details = $session_obj->get_session_details();
    $self->{'child_number'} = 0;

    my $queue_counts  = $session_obj->get_queue_counts();
    my $queue_sizes   = $session_obj->get_queue_sizes();
    my @ACTIVE_QUEUES = grep { $queue_counts->{$_} } @Whostmgr::Transfers::Session::Constants::QUEUES;
    foreach my $queue (@ACTIVE_QUEUES) {
        if ( $queue_counts->{$queue} < $self->{ $queue . '_threads' } ) {
            $self->{ $queue . '_threads' } = $queue_counts->{$queue};
        }
    }

    if ($resume) {
        $self->_master_message('resume');
    }
    else {
        $self->_master_message('start');
        $self->_master_message( 'initiator', $session_details->{'initiator'} );
        $self->_master_message( 'version',   $session_details->{'version'} );

        # Must happen before each queue starts
        foreach my $queue (@ACTIVE_QUEUES) {
            local $self->{'queue'} = $queue;
            $self->_master_message( 'queue_count', $queue_counts->{$queue} );
            $self->_master_message( 'queue_size',  $queue_sizes->{$queue} );
        }
    }

    my $remote_info = $session_obj->remoteinfo();
    $self->_master_message( 'remotehost', $remote_info->{'host'} || $remote_info->{'ssh_host'} || $remote_info->{'sshhost'} );

    # Disconnect so we can safely fork
    $session_obj->disconnect();

    foreach my $queue (@ACTIVE_QUEUES) {
        local $self->{'queue'} = $queue;

        for ( 1 .. $self->{ $queue . '_threads' } ) {
            my $child_pid = $self->_spawn_child( $_, $session_obj );
            $self->{'_children'}{$child_pid} = { 'queue' => $queue, 'child_number' => $_ };
        }
    }

    die "BUG: The session object must not be connected before fork()" if $session_obj->connected();
    $session_obj->reconnect();

    # For testing - this has a while loop in it
    my $children_status = $self->_wait_for_children($queue_counts);

    my $has_paused_child  = grep { $_ == $Whostmgr::Transfers::SessionBase::SESSION_STATES{'PAUSED'} } values %$children_status;
    my $has_aborted_child = grep { $_ == $Whostmgr::Transfers::SessionBase::SESSION_STATES{'ABORTED'} } values %$children_status;

    if ( $has_aborted_child && $session_obj->is_aborted() ) {
        $self->_master_message('abort');
        $session_obj->complete_abort();
    }
    elsif ( $has_paused_child && $session_obj->is_paused() ) {
        $self->_master_message('pause');
        $session_obj->complete_pause();
    }
    else {
        # TODO: create a post_transfer_remove_cleanup()?
        my $authinfo = $session_obj->authinfo();
        if ( $authinfo->{'api_token'} ) {
            try {
                my $cpanel_api = cPanel::PublicAPI->new(
                    user            => $authinfo->{'whmuser'},
                    accesshash      => $authinfo->{'accesshash_pass'},
                    usessl          => 1,                                                                                   # API Tokens require all requests to be done over SSL, so just enable it.
                    ssl_verify_mode => 0,
                    host            => $remote_info->{'host'} || $remote_info->{'ssh_host'} || $remote_info->{'sshhost'},
                );

                $cpanel_api->whm_api(
                    'api_token_revoke',
                    {
                        'api.version' => 1,
                        'token_name'  => $authinfo->{'api_token'},
                    }
                );
            }
            catch {
                # TODO: There is no way to display an error from here to the screen. For now, we are just supressing the error here (See BOO-395 for additional details)
                my $message = "The system failed to remove the generated API token automatically. You must revoke the '$authinfo->{'api_token'}' API token manually from the source server. $_";
                Cpanel::Debug::log_info($message);
            };
        }

        $self->_master_message('complete');
        $session_obj->mark_session_completed();

        Cpanel::Hooks::hook(
            {
                'category' => 'Whostmgr',
                'event'    => 'Transfers::Session',
                'stage'    => 'post',
            },
            { 'session_details' => $session_obj->get_session_details() }
        );
    }

    return;
}

sub _locale {
    eval 'require Cpanel::Locale' if !$INC{'Cpanel/Locale.pm'};
    return $locale ||= Cpanel::Locale->get_handle();
}

# This function is for testing. It waits for the child processes to exit and reports on their exit code
sub _wait_for_children {
    my ( $self, $queue_counts ) = @_;

    my $session_obj        = $self->session();
    my %status_of_children = ();
    my $sent_pausing       = 0;
    my $sent_aborting      = 0;
    while (1) {
        local $?;
        if ( !$sent_aborting && $session_obj->is_aborting() ) {
            $self->_master_message('aborting');
            $sent_aborting = 1;
        }
        elsif ( !$sent_pausing && $session_obj->is_pausing() ) {
            $self->_master_message('pausing');
            $sent_pausing = 1;
        }

        my $child_pid = waitpid( -1, 1 );
        if ( $child_pid == 0 ) {
            Cpanel::TimeHiRes::sleep($TIME_BETWEEN_CHILD_CHECKS);
            next;
        }
        last if ( $child_pid == -1 && $! != EINTR );

        #----------------------------------------------------------------------
        #NOTE: For simplicity's sake, the "protocol" here is that normal exit
        #status is not 0, but one of the values in $W::T::SB::SESSION_STATES
        #as below. An exit status of 0 is actually an (unknown) error!
        #----------------------------------------------------------------------

        my $child_status     = $?;
        my $child_status_obj = Cpanel::ChildErrorStringifier->new($child_status);

        my $child_exit_status = $child_status_obj->error_code() || 0;
        $status_of_children{$child_pid} = $child_exit_status;

        # Check for unexpected status returns, which means the child errored/died
        if (   $child_exit_status != $Whostmgr::Transfers::SessionBase::SESSION_STATES{'PAUSED'}
            && $child_exit_status != $Whostmgr::Transfers::SessionBase::SESSION_STATES{'ABORTED'}
            && $child_exit_status != $Whostmgr::Transfers::SessionBase::SESSION_STATES{'COMPLETED'} ) {
            $self->_handle_child_failure( $child_pid, $queue_counts, $child_status_obj );
        }
    }

    return \%status_of_children;
}

sub _handle_child_failure {
    my ( $self, $child_pid, $queue_counts, $child_status_obj ) = @_;

    my $session_obj = $self->session();
    my ( $item_obj, $item_state ) = $session_obj->get_item_and_state_by_assigned_pid($child_pid);

    my $failed_child_info = delete $self->{'_children'}{$child_pid};

    my ( $queue, $failed_child_number ) = @{$failed_child_info}{qw( queue child_number )};

    local $self->{'queue'} = $queue;

    my $message;
    if ($child_status_obj) {
        if ( $child_status_obj->signal_code() || $child_status_obj->dumped_core() ) {
            $message = $child_status_obj->autopsy();
        }
        elsif ( my $state_code = $child_status_obj->error_code() ) {
            my $state_name = $Whostmgr::Transfers::SessionBase::SESSION_STATE_NAMES{$state_code};
            if ($state_name) {
                $message = _locale()->maketext( 'The “[_1]” processor child exited in the “[_2]” state.', $queue, $state_name );
            }
        }
    }
    $message ||= _locale()->maketext( 'The “[_1]” processor child exited unexpectedly and did not report an error.', $queue );

    if ($item_obj) {
        my $log_file_name = $self->_calculate_log_file_name_by_item_obj( $queue, $item_obj );
        if ( !$self->logs()->is_log_completed($log_file_name) ) {

            # It's possible that the child may have exited after it set the state to failed
            # in the database.  In that case we only need to mark the log file as completed
            # as we do not want to have a duplicate failure message and trip up the UI.
            if ( $item_state != $Whostmgr::Transfers::Session::Constants::QUEUE_STATES{'FAILED'} ) {
                my $log_fh = $self->logs()->append_active_file($log_file_name);
                $session_obj->exec_with_output_directed_to_fh( $log_fh, sub { $item_obj->failed($message); } );
            }
            $self->logs()->mark_log_completed($log_file_name);
        }
    }

    my $number_of_attempts               = ( $self->{ $queue . '_RESTARTS' } ||= 0 );
    my $number_of_retries                = ( $number_of_attempts + 1 );
    my $max_allowed_retries              = $queue_counts->{$queue};
    my $child_terminated_reached_max_rss = ( $child_status_obj && ( $child_status_obj->error_code() || 0 ) == $Whostmgr::Transfers::SessionBase::SESSION_STATES{'REACHEDMAXMEM'} ) ? 1 : 0;

    if ( !$child_terminated_reached_max_rss ) {
        local $self->{'child_number'} = $failed_child_number;

        $self->_master_message( 'child-failed', "$number_of_retries/$max_allowed_retries" );    # do not change this n/n/ format without changing the stringifiers for this (i.e. grep child-failed)

        if ($item_obj) {
            my $size = $item_obj->size();
            $self->_master_message( "failed-item", { 'failure' => $message, 'size' => $size } );
            $self->_mark_item_failed_in_subsequent_queues( $item_obj, $queue, $message, $size );
        }
    }

    # start a new worker process to replace the one that failed if we have items left to process and the session isn't paused
    # only restart a failed child queue_count + 1 times.
    if ( $session_obj->has_next_item($queue) && !$session_obj->is_aborted() && !$session_obj->is_paused() && $number_of_attempts <= $max_allowed_retries ) {
        $session_obj->disconnect();
        my $new_child = $self->_spawn_child( $failed_child_number, $session_obj );
        die "BUG: The session object must not be connected before fork()" if $session_obj->connected();
        $session_obj->reconnect();
        $self->{'_children'}{$new_child} = { 'queue' => $queue, 'child_number' => $failed_child_number };
        if ( !$child_terminated_reached_max_rss ) {

            # avoid incrementing the restarts if it failed
            # as this isn't a reason to not retry.
            $self->{ $queue . '_RESTARTS' } = $number_of_retries;
        }
    }
    else {
        local $self->{'child_number'} = $failed_child_number;
        $self->_master_message('complete');
    }

    return;
}

sub _spawn_child {
    my ( $self, $child_number, $session_obj ) = @_;

    my $queue      = $self->{'queue'};
    my $session_id = $session_obj->id();

    die "BUG: The session object must not be connected before fork()" if $session_obj->connected();

    return Cpanel::ForkAsync::do_in_child(
        sub {
            $self->{'child_number'} = $child_number;
            $0 = "transfer_session - $session_id - $queue:$child_number";
            $session_obj->reconnect();    # need to reconnect after fork();

            # Now in child, reconnect
            $self->_process_items();      # exits
        }
    );
}

# This function gets items from a queue to consume
sub _process_items {
    my ($self) = @_;

    my $queue       = $self->{'queue'};
    my $session_obj = $self->session();

    my $loop_wait  = 0;
    my $sleep_wait = 1;
    my $is_paused  = 0;
    my $is_aborted = 0;

    while (1) {
        $is_paused  = $session_obj->is_paused();
        $is_aborted = $session_obj->is_aborted();

        if ( ( $is_paused || $is_aborted ) && $session_obj->has_next_item($queue) ) {
            $session_obj->disconnect();    # TP TASK 20767 disconnect
                                           # before global destruct
            exit( $Whostmgr::Transfers::SessionBase::SESSION_STATES{ ( $is_aborted ? 'ABORTED' : 'PAUSED' ) } );
        }

        # Periodic check to see if the session is failed
        if ( $loop_wait >= 120 ) {

            # 'queue' will be set to 1 when completed
            last if $session_obj->get_data( 'queue', $queue );
            last if $session_obj->get_session_state() eq $Whostmgr::Transfers::SessionBase::SESSION_STATES{'FAILED'};
            $loop_wait = 0;
        }
        else {
            $loop_wait += $sleep_wait;
        }

        # Reap children that may be left over
        my $child_pid = waitpid( -1, 1 );

        # queue is one of @Whostmgr::Transfers::Session::Constants::QUEUES
        my $queue_state = $session_obj->dequeue_next_item($queue);
        if ( $queue_state == $Whostmgr::Transfers::Session::Constants::QUEUE_FETCHED ) {
            $self->_master_message('start');
            my ( $item_state, $item_message ) = $self->_process_dequeued_item();
            $sleep_wait = 1;

            if ( $item_state == $Whostmgr::Transfers::SessionBase::SESSION_STATES{'REACHEDMAXMEM'} ) {
                $session_obj->disconnect();    # TP TASK 20767 disconnect
                                               # before global destruct

                exit $Whostmgr::Transfers::SessionBase::SESSION_STATES{'REACHEDMAXMEM'};
            }
        }
        elsif ( $queue_state == $Whostmgr::Transfers::Session::Constants::QUEUE_BLOCKED ) {

            # Progressive sleeping
            sleep($sleep_wait);
            $sleep_wait++ if $sleep_wait < 5;
        }
        else {    # QUEUE_EMPTY state
            last;
        }

        $child_pid = waitpid( -1, 1 );
    }

    $self->_master_message('complete');
    $session_obj->disconnect();    # TP TASK 20767 disconnect
                                   # before global destruct

    exit( $Whostmgr::Transfers::SessionBase::SESSION_STATES{'COMPLETED'} );
}

sub _master_message {
    my ( $self, $action, $message ) = @_;

    my ( $queue, $local_item, $item, $item_type, $item_name, $logfile );
    my $child_number = $self->{'child_number'};
    my $pid          = $$;

    $queue = $self->{'queue'};
    if ( my $item_obj = $self->current_item() ) {
        $item       = $item_obj->item();
        $item_type  = $item_obj->item_type();
        $item_name  = $item_obj->item_name();
        $local_item = $item_obj->local_item();
        $logfile    = $self->_calculate_log_file_name($queue);
    }

    return $self->{'session_obj'}->output_message(
        'control',
        {
            'child_number' => $child_number,
            'action'       => $action,
            'time'         => time(),
            ( $item       ? ( 'item'       => $item )       : () ),
            ( $local_item ? ( 'local_item' => $local_item ) : () ),
            ( $item_type  ? ( 'item_type'  => $item_type )  : () ),
            ( $item_name  ? ( 'item_name'  => $item_name )  : () ),
            ( $queue      ? ( 'queue'      => $queue )      : () ),
            ( $logfile    ? ( 'logfile'    => $logfile )    : () ),
            ( $message    ? ( 'msg'        => $message )    : () ),
        }
    );
}

# This function consumes the dequeued item
sub _process_dequeued_item {
    my ($self) = @_;

    my $session_id = $self->session()->id();
    my $item_obj   = $self->current_item();

    my $queue = $item_obj->queue();

    my $item      = $item_obj->item();
    my $item_type = $item_obj->item_type();
    my $item_name = $item_obj->item_name();
    my $size      = $item_obj->size();

    # Make sure the last item was not a transfer as the current item may not be
    if ( $item_obj->is_transfer_item() ) {
        Whostmgr::Transfers::State::start_transfer();
    }
    else {
        Whostmgr::Transfers::State::end_transfer();
    }

    my $now = time();

    my $log_file_name = $self->_calculate_log_file_name($queue);

    my $method = $queue;
    $method =~ tr/A-Z/a-z/;

    $self->_master_message( "process-item", $log_file_name );
    $self->_master_message( "start-item",   { 'size' => $size } );

    my $log_fh      = $self->logs()->create_active_file($log_file_name);
    my $session_obj = $self->session();
    my $maxrss;

    my ( $result_ref, $error_trap ) = $session_obj->exec_with_output_directed_to_fh(
        $log_fh,
        sub {
            $item_obj->set_percentage(0);
            $item_obj->start($queue);
            my @results = $item_obj->$method();

            $maxrss = Cpanel::Rusage::get_self()->{'maxrss'};
            if ( $maxrss > _MAX_ALLOWED_RSS_KIB() ) {
                my $warning = "Transfer queue $queue process $$ consumes excess memory (RSS=$maxrss KiB)";
                $warning .= "; The memory limit was reached while processing the item “$item” with name “$item_name” of type “$item_type”";
                $warning .= "; This process will end and a new processor will take over if there is still work to do …";
                Cpanel::Debug::log_info($warning);    # Avoid red banner in UI as this is a warning not a failure
                if ( $item_obj->{'account_restore_obj'} ) {
                    $item_obj->{'account_restore_obj'}->warn($warning);
                }
            }

            $item_obj->write_summary_message();
            return @results;
        }
    );

    my $failed      = 0;
    my $return_code = $result_ref->[0];
    my $return_msg  = $result_ref->[1];

    my $item_data = { 'size' => $size };

    try {
        $item_data->{'warnings'}        = $item_obj->warnings_count();
        $item_data->{'skipped_items'}   = $item_obj->skipped_items_count();
        $item_data->{'dangerous_items'} = $item_obj->dangerous_items_count();
        $item_data->{'altered_items'}   = $item_obj->altered_items_count();

        $item_data->{'contents'}{'warnings'}        = $item_obj->warnings();
        $item_data->{'contents'}{'dangerous_items'} = $item_obj->dangerous_items();
        $item_data->{'contents'}{'skipped_items'}   = $item_obj->skipped_items();
        $item_data->{'contents'}{'altered_items'}   = $item_obj->altered_items();
    };

    if ($error_trap) {
        $failed = $error_trap || 'Internal code error';
        $item_data->{'failure'} = $failed;
        $self->_master_message( "failed-item", $item_data );

        my $message = $failed;
        chomp($message);

        if ( !$result_ref || !ref $result_ref ) {
            $result_ref = [ $Whostmgr::Transfers::Session::Constants::QUEUE_STATES{'FAILED'}, $message ];
        }

        # Need to force a failure because we died
        $session_obj->exec_with_output_directed_to_fh( $log_fh, sub { $item_obj->failed($message); } );
    }
    elsif ( !$return_code || $return_code < $Whostmgr::Transfers::Session::Constants::MIN_VALID_RETURN_CODE ) {
        $failed = $return_msg || ( ( scalar ref $item_obj ) . ": Internal Failure: Missing results from $method" );
        $item_data->{'failure'} = $failed;

        $self->_master_message( "failed-item", $item_data );
        $session_obj->exec_with_output_directed_to_fh( $log_fh, sub { $item_obj->failed($failed); } );
    }
    elsif ( $return_code == $Whostmgr::Transfers::Session::Constants::QUEUE_STATES{'FAILED'} ) {
        $failed = $return_msg || 'Generic failure state';
        $item_data->{'failure'} = $failed;
        $self->_master_message( "failed-item", $item_data );
    }
    else {
        $item_data->{'message'} = $return_msg;
        if ( $item_data->{'warnings'} || $item_data->{'skipped_items'} || $item_data->{'dangerous_items'} || $item_data->{'altered_items'} ) {
            $self->_master_message( "warning-item", $item_data );
        }
        else {
            $self->_master_message( "success-item", $item_data );
        }
        $session_obj->exec_with_output_directed_to_fh( $log_fh, sub { $item_obj->failed($return_msg); } ) if !$return_code;
    }

    if ($failed) {
        $self->_mark_item_failed_in_subsequent_queues( $item_obj, $queue, $failed, $size );
    }

    close($log_fh);

    $self->logs()->mark_log_completed($log_file_name);

    if ( $maxrss > _MAX_ALLOWED_RSS_KIB() ) {
        $return_code = $Whostmgr::Transfers::SessionBase::SESSION_STATES{'REACHEDMAXMEM'};
    }

    return ( $return_code, $return_msg );
}

sub _calculate_log_file_name {
    my ( $self, $queue ) = @_;

    return $self->_calculate_log_file_name_by_item_obj( $queue, $self->current_item() );
}

sub _calculate_log_file_name_by_item_obj {
    my ( $self, $queue, $item_obj ) = @_;

    my $item      = $item_obj->item();
    my $item_type = $item_obj->item_type();

    return "item-${queue}_${item_type}_${item}";
}

sub _mark_item_failed_in_subsequent_queues {
    my ( $self, $item_obj, $current_queue, $message, $size ) = @_;

    my $session_obj = $self->session();

    # We need to mark the item as done for all subsequent queues upon failure
    my $found_queue = 0;
    foreach my $queue (@Whostmgr::Transfers::Session::Constants::QUEUES) {
        if ( $queue eq $current_queue ) {
            $found_queue = 1;
        }
        elsif ($found_queue) {
            local $self->{'queue'} = $queue;

            $self->_master_message( "start-item",  { 'size'    => $size } );                       # must start before fail
            $self->_master_message( "failed-item", { 'failure' => $message, 'size' => $size } );

            my $log_file_name = $self->_calculate_log_file_name_by_item_obj( $queue, $item_obj );
            my $log_fh        = $self->logs()->create_active_file($log_file_name);

            # Need to force a failure because we died
            $session_obj->exec_with_output_directed_to_fh(
                $log_fh,
                sub {
                    $item_obj->start($queue);
                    $item_obj->failed($message);
                }
            );
            $self->logs()->mark_log_completed($log_file_name);
        }
    }
    return;
}

sub _reduce_thread_counts_if_low_disk_space {
    my ($self) = @_;

    my @to_check = (
        {
            'target' => Cpanel::Filesys::Home::get_homematch_with_most_free_space()    #
        }
    );

    my $remote_info = $self->session()->remoteinfo();

    if ( $remote_info->{'pkgacct-target'} && length $remote_info->{'pkgacct-target-blocks_free'} ) {
        push @to_check, {
            'host'               => ( $remote_info->{'host'} || $remote_info->{'sship'} || 'source' ),    #
            'target'             => $remote_info->{'pkgacct-target'},                                     #
            'target_blocks_free' => $remote_info->{'pkgacct-target-blocks_free'},                         #
            'target_inodes_free' => $remote_info->{'pkgacct-target-inodes_free'}                          #
        };
    }

    my $largest_source_sizes_ref = $self->_get_largest_source_sizes();
    foreach my $disk (@to_check) {
        my ( $disk_ok, $disk_msg, $reduced );

        my $target             = $disk->{'target'};
        my $host               = $disk->{'host'};
        my $target_blocks_free = $disk->{'target_blocks_free'};
        my $target_inodes_free = $disk->{'target_inodes_free'};

        my $sizes_ref = [ @{$largest_source_sizes_ref} ];    # make a copy

        while ( @{$sizes_ref} ) {

            #TODO: Make error reporting distinguish between an actual *failure*
            #versus when we successfully determined that there is not enough space.
            if ($host) {
                ( $disk_ok, $disk_msg ) = Cpanel::DiskCheck::target_on_host_has_enough_free_space_to_fit_source_sizes(
                    'source_sizes'       => $sizes_ref,
                    'target'             => $target,
                    'host'               => $host,
                    'output_coderef'     => \&Cpanel::DiskCheck::blackhole_output,
                    'target_blocks_free' => $target_blocks_free,
                    'target_inodes_free' => $target_inodes_free,
                );
            }
            else {
                ( $disk_ok, $disk_msg ) = Cpanel::DiskCheck::target_has_enough_free_space_to_fit_source_sizes(
                    'source_sizes'   => $sizes_ref,
                    'target'         => $target,
                    'output_coderef' => \&Cpanel::DiskCheck::blackhole_output,
                );
            }

            last if $disk_ok;

            # Reduce by one and lets see if we can pass the disk space
            if ( pop @{$sizes_ref} ) {
                last if !@{$sizes_ref};    # however we don't want to continue if we run out of threads to reduce
                $reduced += $self->_reduce_thread_counts_to_maximum( scalar @{$sizes_ref} );
            }
        }

        $self->_log_disk_space_and_thread_reductions( $disk_ok, $disk_msg, scalar @{$sizes_ref}, $reduced );

    }
    return scalar @to_check;
}

sub _get_largest_source_sizes {
    my ($self)    = @_;
    my $max       = $self->_get_max_threads();
    my $items_ref = $self->{'session_obj'}->fetch_largest_items($max);

    my $type         = $self->{'session_obj'}->can_stream() ? 'streamed' : 'raw_copy';
    my @source_sizes = map {
        { $type => $_->{'size'} },
    } @{$items_ref};

    return \@source_sizes;
}

sub _log_disk_space_and_thread_reductions {
    my ( $self, $disk_ok, $disk_msg, $number_of_threads, $reduced ) = @_;

    $logger ||= Cpanel::Logger->new();
    $disk_msg = '' unless defined $disk_msg;
    $number_of_threads ||= 1;    # never display 0 thread
    if ( $reduced && $disk_ok ) {
        $logger->warn("Transfer threads reduced to “$number_of_threads” in order to accommodate low disk space.");
    }
    elsif ($reduced) {
        $logger->warn("Transfer threads reduced to “$number_of_threads”: $disk_msg");
    }
    elsif ( !$disk_ok ) {
        $logger->warn($disk_msg);
    }

    return 1;
}

sub _get_max_threads {
    my ($self) = @_;
    my $max = 1;
    foreach my $queue (@Whostmgr::Transfers::Session::Constants::QUEUES) {
        my $thread_type = $queue . '_threads';
        if ( $self->{$thread_type} > $max ) { $max = $self->{$thread_type}; }
    }
    return $max;
}

1;
