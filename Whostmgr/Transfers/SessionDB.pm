package Whostmgr::Transfers::SessionDB;

# cpanel - Whostmgr/Transfers/SessionDB.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use base 'Whostmgr::Transfers::SessionBase';

use Cpanel::Exception                    ();
use Whostmgr::Transfers::Session::Config ();
use Whostmgr::Transfers::Session::Logs   ();

use Try::Tiny;

my $locale;

sub create_session {
    my ( $self, $initiator ) = @_;

    require Whostmgr::Transfers::Session;
    return Whostmgr::Transfers::Session->new( 'create' => 1, 'master_dbh' => $self->{'_master_dbh'}, 'initiator' => $initiator );
}

sub get_session {
    my ( $self, $session_id ) = @_;

    return if !$self->session_id_exists($session_id);

    require Whostmgr::Transfers::Session;
    return Whostmgr::Transfers::Session->new( 'id' => $session_id, 'master_dbh' => $self->{'_master_dbh'} );
}

sub get_sessions {
    my ( $self, $states, $initiator ) = @_;

    if ( !ref $states ) {
        $states = [$states];
    }

    my $sessions_hr = $self->list_session_details( $states, $initiator );

    my @sessions = sort keys %$sessions_hr;
    return @sessions;
}

sub list_session_details {
    my ( $self, $states, $initiator ) = @_;

    if ( !ref $states ) {
        $states = [$states];
    }

    foreach my $state ( @{$states} ) {
        if ( !defined $Whostmgr::Transfers::SessionBase::SESSION_STATES{$state} ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'The parameter “[_1]” was passed the invalid value of “[_2]”.', [ 'states', $state ] );
        }
    }

    # validated above
    my $safe_state_sql = "(" . join( ',', map { $Whostmgr::Transfers::SessionBase::SESSION_STATES{$_} } @{$states} ) . ")";

    if ($initiator) {
        return $self->master_sql(
            'selectall_hashref',
            [
                "SELECT *, strftime('%s',`starttime`) AS starttime_unix, strftime('%s',`endtime`) AS endtime_unix from sessions
               where initiator=? and state IN $safe_state_sql", 'sessionid', {}, $initiator
            ]
        );
    }
    else {
        return $self->master_sql(
            'selectall_hashref',
            [
                "SELECT *, strftime('%s',`starttime`) AS starttime_unix, strftime('%s',`endtime`) AS endtime_unix from sessions
            where state IN $safe_state_sql", 'sessionid', {}
            ]
        );
    }
}

sub delete_session {
    my ( $self, $session_id ) = @_;

    # Session logs may have already been removed, in which case it will error
    if ( !$self->can('logs') ) {
        try { Whostmgr::Transfers::Session::Logs->new( 'id' => $session_id )->delete_log(); };
    }

    return ( $self->_delete_session($session_id) ) ? 1 : undef;
}

sub expunge_expired_sessions {
    my ($self) = @_;

    my $now      = time();
    my $max_ttl  = $Whostmgr::Transfers::Session::Config::MAX_SESSION_AGE;
    my $max_idle = $Whostmgr::Transfers::Session::Config::MAX_IDLE_TIME;

    my $sessions_hashref = $self->list_session_details( [ keys %Whostmgr::Transfers::SessionBase::SESSION_STATES ] );
    for my $session_id ( keys %$sessions_hashref ) {
        my $starttime = $sessions_hashref->{$session_id}{'starttime_unix'};
        if ( ( $starttime + $max_ttl ) < $now ) {
            $self->delete_session($session_id);
            next;
        }
        if ( $sessions_hashref->{$session_id}{'state'} eq $Whostmgr::Transfers::SessionBase::SESSION_STATES{'PENDING'} && ( $starttime + $max_idle ) < $now ) {
            $self->delete_session($session_id);
            next;
        }
        if (   $sessions_hashref->{$session_id}{'state'} eq $Whostmgr::Transfers::SessionBase::SESSION_STATES{'RUNNING'}
            || $sessions_hashref->{$session_id}{'state'} eq $Whostmgr::Transfers::SessionBase::SESSION_STATES{'PAUSING'} ) {
            my $session          = $self->get_session($session_id);
            my $log_time_hashref = $session->logs()->get_log_modify_times();

            my $fail_session = 1;
            for my $log_file ( keys %$log_time_hashref ) {
                if ( $log_time_hashref->{$log_file} && ( $log_time_hashref->{$log_file} + $max_idle ) >= $now ) {
                    $fail_session = 0;
                    last;
                }
            }

            next if !$fail_session;

            $session->failed() if $session->_has_current_item();
            $self->mark_session_failed($session_id);
            $session->logs()->mark_session_completed();
        }
    }

    return 1;
}

1;
