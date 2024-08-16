package Whostmgr::Transfers::Session::Item;

# cpanel - Whostmgr/Transfers/Session/Item.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

our $VERSION = '1.3';

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::Session::Item

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Destruct::DestroyDetector';

use Try::Tiny;

use Cpanel::Imports;

use Carp                                    ();
use Cpanel::Signals                         ();
use Cpanel::Locale                          ();
use Cpanel::Exception                       ();
use Whostmgr::Remote                        ();
use Whostmgr::Remote::CommTransport         ();
use Whostmgr::Transfers::Session::Constants ();

our $ABORTABLE     = 1;
our $NOT_ABORTABLE = 0;

use constant {

    # Subclasses can override this to control whether a user-authenticated
    # transfer can enqueue an item of that subclass’s type. This provides
    # a sanity-check for API callers so that they don’t, e.g., enqueue
    # AccountRemoteRoot under a user-authenticated transfer.
    _IS_ROOT_USABLE => 1,
    _IS_USER_USABLE => 0,
};

#----------------------------------------------------------------------

=head1 CLASS METHODS

=head2 I<CLASS>->prevalidate_or_die( $SESSION_OBJ, \%OPTS )

Throws an exception if any element of %OPTS is invalid and if I<CLASS>
defines a C<_prevalidate()> method. The actual exception thrown comes
from that method, so each subclass can throw whatever error makes the
most sense for its context.

$SESSION_OBJ is a L<Whostmgr::Transfers::Session> instance.

=cut

sub prevalidate_or_die ( $class, $session_obj, $input_hr ) {

    # This only looks for the specific “initiator” types that come from
    # the Preflight::Remote(Root|User) modules. Everything else is allowed.
    $class->_check_authn_forbiddance($session_obj);

    $class->_prevalidate( $session_obj, $input_hr );

    return;
}

sub _check_authn_forbiddance ( $class, $session_obj ) {

    # This prevents folks who called the API’s
    # create_remote_user_transfer_session from inadvertently adding
    # a transfer item that they can’t use.
    if ( $session_obj->initiator() eq Whostmgr::Transfers::Session::Constants::USER_API_SESSION_INITIATOR ) {
        if ( !$class->_IS_USER_USABLE() ) {
            die locale()->maketext('User-authenticated transfer sessions cannot enqueue items of this type. Try again from a root-authenticated transfer session.') . "\n";
        }
    }

    # This, likewise, prevents create_remote_root_transfer_session
    # callers from using the wrong transfer items.
    elsif ( $session_obj->initiator() eq Whostmgr::Transfers::Session::Constants::ROOT_API_SESSION_INITIATOR ) {
        if ( !$class->_IS_ROOT_USABLE() ) {
            die locale()->maketext('Root-authenticated transfer sessions cannot enqueue items of this type. Try again from a user-authenticated transfer session.') . "\n";
        }
    }

    return;
}

sub _prevalidate {
    return;
}

sub new {
    my ( $class, %opts ) = @_;

    my $self = { %opts, '_seen_percentages' => {} };

    foreach my $required_key (qw(input item session_obj queue item_type size)) {
        if ( !defined $self->{$required_key} ) {
            die "“" . ( caller(0) )[3] . "” requires the “" . $required_key . "” key in order to be created.";
        }
    }

    return bless $self, $class;

}

#----------------------------------------------------------------------

=head2 INSTANCE METHODS

=cut

sub set_key {
    my ( $self, $key, $value ) = @_;

    return $self->session()->update_hashref_key( $self->item_type(), $self->item(), $key, $value );
}

sub type {
    my ($self) = @_;

    return ( split( m{::}, ref $self ) )[-1];
}

# Base class STUB which is overwritten
sub local_item {
    return;
}

sub item_name {
    my ($self) = @_;

    return $self->module_info()->{'item_name'};
}

sub item_type {
    my ($self) = @_;

    return $self->_get_required_key('item_type');
}

sub size {
    my ($self) = @_;

    return $self->_get_required_key('size');
}

sub item {
    my ($self) = @_;

    return $self->_get_required_key('item');
}

sub queue {
    my ($self) = @_;

    return $self->_get_required_key('queue');
}

sub session {
    my ($self) = @_;

    return $self->_get_required_key('session_obj');
}

sub set_warnings_count {
    my ( $self, $count ) = @_;

    return ( $self->{'warnings_count'} = $count );
}

#NOTE: This appears to expect each message to be a hashref
#like:
#
#   { msg => [ '...' ] }
#
#Should this die() if it receives something that doesn’t fit that pattern?
sub set_warnings {
    my ( $self, $msgs ) = @_;

    $self->{'warnings'} = $msgs;

    return $self->set_warnings_count( scalar @{$msgs} );
}

sub has_warnings {
    my ($self) = @_;

    return $self->{'warnings_count'} ? 1 : 0;
}

sub warnings {
    my ($self) = @_;

    return $self->{'warnings'};
}

sub warnings_count {
    my ($self) = @_;

    return $self->{'warnings_count'} || 0;
}

sub set_skipped_items_count {
    my ( $self, $count ) = @_;

    return ( $self->{'skipped_items_count'} = $count );
}

sub set_skipped_items {
    my ( $self, $msgs ) = @_;

    $self->{'skipped_items'} = $msgs;

    return $self->set_skipped_items_count( scalar @{$msgs} );
}

sub skipped_items {
    my ($self) = @_;

    return $self->{'skipped_items'};
}

sub has_skipped_items {
    my ($self) = @_;

    return $self->{'skipped_items_count'} ? 1 : 0;
}

sub skipped_items_count {
    my ($self) = @_;

    return $self->{'skipped_items_count'} || 0;
}

sub set_dangerous_items_count {
    my ( $self, $count ) = @_;

    return ( $self->{'dangerous_items_count'} = $count );
}

sub set_dangerous_items {
    my ( $self, $msgs ) = @_;

    $self->{'dangerous_items'} = $msgs;

    return $self->set_dangerous_items_count( scalar @{$msgs} );
}

sub dangerous_items {
    my ($self) = @_;

    return $self->{'dangerous_items'};
}

sub has_dangerous_items {
    my ($self) = @_;

    return $self->{'dangerous_items_count'} ? 1 : 0;
}

sub dangerous_items_count {
    my ($self) = @_;

    return $self->{'dangerous_items_count'} || 0;
}

sub set_altered_items_count {
    my ( $self, $count ) = @_;

    return ( $self->{'altered_items_count'} = $count );
}

sub set_altered_items {
    my ( $self, $msgs ) = @_;

    $self->{'altered_items'} = $msgs;

    return $self->set_altered_items_count( scalar @{$msgs} );
}

sub altered_items {
    my ($self) = @_;

    return $self->{'altered_items'};
}

sub has_altered_items {
    my ($self) = @_;

    return $self->{'altered_items_count'} ? 1 : 0;
}

sub altered_items_count {
    my ($self) = @_;

    return $self->{'altered_items_count'} || 0;
}

sub get_percentage {
    return $_[0]->{'_current_percentage'};
}

sub set_percentage {
    my ( $self, $percentage ) = @_;

    return if ( $self->{'_seen_percentages'}{$percentage} );

    $self->{'_current_percentage'} = $percentage;
    $self->{'_seen_percentages'}{$percentage} = 1;             # prevent duplicate output

    return $self->message(
        'control',
        { 'action' => 'percentage', 'percentage' => $percentage, 'time' => time() }
    );

}

sub message {
    $_[2]->{'time'} ||= time() if ref $_[2];
    $_[0]->session()->get_output_obj()->message( @_[ 1 .. $#_ ] );
    return 1;                                                  # print return is not reliable
}

sub success {
    my ( $self, $localized_string ) = @_;

    return $self->_finish( 'success', $localized_string );
}

sub failed {
    my ( $self, $localized_string ) = @_;

    return $self->_finish( 'failed', $localized_string );
}

sub exec_path {
    my ( $self, $exec_path, $failure_path, $abortable ) = @_;

    if ( defined($failure_path) && ref $failure_path ne 'ARRAY' ) {

        # Implementor error
        die "Internal error: exec_path's failure_path must be an arrayref";
    }

    my ( $status, $statusmsg, $exec_error );
    try {
        foreach my $count ( 0 .. $#$exec_path ) {
            my $func = $exec_path->[$count];
            ( $status, $statusmsg ) = $self->$func();
            last if !$status || $count == $#$exec_path;

            if ( defined $abortable && $abortable == $ABORTABLE ) {
                if ( Cpanel::Signals::signal_needs_to_be_handled('TERM') ) {
                    $status    = 0;
                    $statusmsg = $self->_locale()->maketext("Aborted.");
                    last;
                }
                elsif ( Cpanel::Signals::signal_needs_to_be_handled('USR1') ) {

                    #TODO: call Whostmgr::Transfers::State::should_skip(); which should have been
                    #told about what item we are transfering in the form of
                    # item-TRANSFER_AccountRemoteRoot_customer1  so it can
                    # look for a skip-TRANSFER_AccountRemoteRoot_customer1 that will be created
                    # by the process that is sending USR1 so we ensure that by the time USR1
                    # is sent, we have not started working on a different account and we skip
                    # the wrong one.  There needs to be a notice to the person calling the skip
                    # as well that it will attempt to skip but it can only do so while the transfer
                    # is in progress and if it finishes before the skip happens it will continue on.
                    $status    = 0;
                    $statusmsg = $self->_locale()->maketext("Skipped.");
                    last;
                }
            }
        }
    }
    catch {
        $exec_error = $_;
    };

    if ( $exec_error || !$status ) {
        foreach my $fail_func ( @{$failure_path} ) {
            $self->$fail_func();
        }

        my $err_str;
        if ($exec_error) {
            $err_str = $exec_error;
        }
        else {
            $err_str = $statusmsg;
        }

        return $self->failed( Cpanel::Exception::get_string($err_str) );
    }

    return $self->success();
}

sub start {
    my ( $self, $queue ) = @_;

    my $item_name  = $self->item_name();
    my $item       = $self->item();
    my $local_item = $self->local_item();

    return $self->message(
        'start',
        {
            'msg' => [
                ( $local_item && $item ne $local_item )
                ? $self->_locale()->maketext( "Starting “[_1]” for “[_2]” “[_3]” → “[_4]”.[comment,## no extract maketext (will be done via task 32670)]", $queue, $item_name, $item, $local_item )
                : $self->_locale()->maketext( "Starting “[_1]” for “[_2]” “[_3]”.[comment,## no extract maketext (will be done via task 32670)]", $queue, $item_name, $item )
            ]
        }
    );
}

sub _finish {
    my ( $self, $message_type, $localized_string ) = @_;

    my $status_phrase;
    my ( $result_state, $session_state_func );

    if ( $message_type eq 'success' ) {
        $session_state_func = 'mark_item_as_completed';
        $result_state       = 'COMPLETED';
        $status_phrase      = $self->_locale()->maketext('Success.');
    }
    elsif ( $message_type eq 'failed' ) {
        $session_state_func = 'mark_item_as_failed';
        $result_state       = 'FAILED';
        $status_phrase      = $self->_locale()->maketext( 'Failed: [_1]', $localized_string );
    }
    else {
        die "Unrecognized message type: “$message_type”!";
    }

    my $session_obj = $self->session();

    $self->set_percentage(100);

    $self->message(
        $message_type,
        { 'msg' => [$status_phrase] }
    );

    # UI updates here
    $session_obj->$session_state_func($self);

    no warnings 'once';

    return ( $Whostmgr::Transfers::Session::Constants::QUEUE_STATES{$result_state}, $localized_string );
}

sub _locale {
    my $self = shift;

    return ( $self->{'_locale'} ||= Cpanel::Locale->get_handle() );
}

sub _get_required_key {
    my ( $self, $key ) = @_;

    if ( defined $self->{$key} ) {
        return $self->{$key};
    }

    Carp::confess("The required key “$key” is missing from the object");
}

sub validate_input {
    my ( $self, $required_fields ) = @_;

    foreach my $required_object ( @{$required_fields} ) {
        if ( ref $required_object ) {
            my $key = $required_object->[0];
            foreach my $subkey ( @{ $required_object->[1] } ) {
                if ( !defined $self->{$key}->{$subkey} ) {
                    return ( 0, $self->_locale()->maketext( "“[_1]” failed to create “[_2]” in “[_3]”.", ( caller(1) )[3], $subkey, $key ) );
                }
            }
        }
        elsif ( !defined $self->{$required_object} ) {
            return ( 0, $self->_locale()->maketext( "“[_1]” failed to create “[_2]”.", ( caller(1) )[3], $required_object ) );
        }
    }
    return ( 1, "validate_input" );
}

sub create_remote_object {
    my ($self) = @_;

    my $remoteobj;

    my $comm_xport = $self->{'authinfo'}{'comm_transport'};

    my $cpsrvd_tls_verification = Whostmgr::Remote::CommTransport::get_cpsrvd_tls_verification($comm_xport);

    if ($cpsrvd_tls_verification) {
        require Whostmgr::Remote::CommandStream::Legacy;
        $remoteobj = Whostmgr::Remote::CommandStream::Legacy->new(
            {
                %{ $self->{'authinfo'} }{ 'user', 'password' },
                tls_verification => $cpsrvd_tls_verification,
                'host'           => $self->{'remote_info'}->{'sship'},
            },
        );
    }
    else {
        ( my $new_ok, $remoteobj ) = Whostmgr::Remote->new_trap_exceptions(
            {
                %{ $self->{'authinfo'} },
                'host' => $self->{'remote_info'}->{'sship'},
                'port' => $self->{'remote_info'}->{'sshport'},
                ( $self->{'session_info'}->{'session_timeout'} ? ( 'timeout' => $self->{'session_info'}->{'session_timeout'} ) : () ),
                'use_global_connection_cache' => 1,
            }
        );

        return ( 0, $remoteobj ) if !$new_ok;
    }

    $self->{'remoteobj'} = $remoteobj;

    if ( !$self->{'remoteobj'} ) {
        return ( 0, "Failed to create remote object" );
    }

    return ( 1, "Created remote object" );
}

sub write_summary_message {
    my ($self) = @_;

    return if !$self->{'account_restore_obj'};    # only do this for account restores

    my $warnings        = $self->{'account_restore_obj'}->get_warnings();
    my $skipped_items   = $self->{'account_restore_obj'}->get_skipped_items();
    my $dangerous_items = $self->{'account_restore_obj'}->get_dangerous_items();
    my $altered_items   = $self->{'account_restore_obj'}->get_altered_items();

    if ( ref $skipped_items ) {
        $self->set_skipped_items($skipped_items);
    }
    if ( ref $dangerous_items ) {
        $self->set_dangerous_items($dangerous_items);
    }
    if ( ref $altered_items ) {
        $self->set_altered_items($altered_items);
    }
    if ( ref $warnings ) {
        $self->set_warnings($warnings);
    }
    if ( $self->get_percentage() < 92 ) {
        $self->set_percentage(92);
    }

    return $self->{'output_obj'}->message( 'control', { 'time' => time(), 'action' => 'summary', 'warnings' => $warnings, 'skipped_items' => $skipped_items, 'dangerous_items' => $dangerous_items, 'altered_items' => $altered_items } );
}

sub is_transfer_item {
    return 1;
}

sub allow_non_root_enqueue {
    return 0;
}

# Whenever the session object and $self hold references to each other,
# one of those references has to be weakened or else we get a memory leak.
sub weaken_session ($self) {
    require Scalar::Util;
    Scalar::Util::weaken( $self->{'session_obj'} );

    return $self;
}

sub session_obj_init {
    my ($self) = @_;

    $self->{'session_obj'} ||= $self->session();
    $self->{'output_obj'}  ||= $self->{'session_obj'}->get_output_obj();

    if ( !$self->{'_loaded_session_data'}++ ) {
        my $data = $self->{'session_obj'}->get_data( [qw(options authinfo remote session)] );

        $self->{'options'}      ||= $data->{'options'}  if $data->{'options'};
        $self->{'authinfo'}     ||= $data->{'authinfo'} if $data->{'authinfo'};
        $self->{'remote_info'}  ||= $data->{'remote'}   if $data->{'remote'};
        $self->{'session_info'} ||= $data->{'session'}  if $data->{'session'};

        # can_stream may not be available if we do not have
        # a remote
        $self->{'can_stream'} = $self->{'remote_info'}->{'can_stream'} ? 1 : 0;
        $self->{'can_rsync'}  = $self->{'remote_info'}->{'can_rsync'}  ? 1 : 0;
    }

    return $self->{'_loaded_session_data'};
}

1;
