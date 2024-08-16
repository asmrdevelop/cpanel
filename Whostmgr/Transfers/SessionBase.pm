package Whostmgr::Transfers::SessionBase;

# cpanel - Whostmgr/Transfers/SessionBase.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;
use DBD::SQLite ();
use parent      qw( Whostmgr::Transfers::Session::DBBackend );

use Cpanel::Carp                         ();
use Whostmgr::Transfers::Session::Config ();
use Try::Tiny;

our %SESSION_STATES = (
    'PENDING'       => 0,
    'REACHEDMAXMEM' => 10,
    'RUNNING'       => 20,
    'PAUSING'       => 50,
    'ABORTING'      => 60,
    'PAUSED'        => 70,
    'COMPLETED'     => 100,
    'ABORTED'       => 150,
    'FAILED'        => 200,
);

our %SESSION_STATE_NAMES = reverse %SESSION_STATES;
our $SESSIONS_TABLE      = 'sessions';

sub mark_session_completed {
    my ( $self, $session_id ) = @_;

    return $self->_set_session_state( $session_id, $Whostmgr::Transfers::SessionBase::SESSION_STATES{'COMPLETED'} );
}

sub mark_session_failed {
    my ( $self, $session_id ) = @_;

    return $self->_set_session_state( $session_id, $Whostmgr::Transfers::SessionBase::SESSION_STATES{'FAILED'} );
}

sub start_pause {
    my ( $self, $session_id ) = @_;

    return $self->_set_session_state( $session_id, $Whostmgr::Transfers::SessionBase::SESSION_STATES{'PAUSING'} );
}

sub complete_pause {
    my ( $self, $session_id ) = @_;

    return $self->_set_session_state( $session_id, $Whostmgr::Transfers::SessionBase::SESSION_STATES{'PAUSED'} );
}

sub start_abort {
    my ( $self, $session_id ) = @_;

    return $self->_set_session_state( $session_id, $Whostmgr::Transfers::SessionBase::SESSION_STATES{'ABORTING'} );
}

sub complete_abort {
    my ( $self, $session_id ) = @_;

    return $self->_set_session_state( $session_id, $Whostmgr::Transfers::SessionBase::SESSION_STATES{'ABORTED'} );
}

sub resume {
    my ( $self, $session_id ) = @_;

    return $self->_set_session_state( $session_id, $Whostmgr::Transfers::SessionBase::SESSION_STATES{'RUNNING'} );
}

sub set_source_host {
    my ( $self, $session_id, $source_host ) = @_;

    my $quoted_session_id  = $self->quote($session_id);
    my $quoted_source_host = $self->quote($source_host);

    return $self->master_do("UPDATE $SESSIONS_TABLE set source_host=$quoted_source_host where sessionid=$quoted_session_id;");
}

sub get_source_host {
    my ( $self, $session_id ) = @_;

    my $quoted_session_id = $self->quote($session_id);

    my $data = $self->master_sql( 'selectcol_arrayref', ["SELECT source_host from $SESSIONS_TABLE where sessionid=$quoted_session_id;"] );

    return $data->[0];
}

sub session_id_exists {
    my ( $self, $session_id ) = @_;

    my $quoted_session_id = $self->quote($session_id);
    my $data              = $self->master_sql( 'selectall_arrayref', ["SELECT sessionid from $SESSIONS_TABLE where sessionid=$quoted_session_id;"] );
    if ( ref $data ) {
        $data = $data->[0][0];
    }

    if ( $data && $data eq $session_id ) { return 1; }

    return 0;
}

sub get_session_details {
    my ( $self, $session_id ) = @_;

    return $self->master_sql( 'selectrow_hashref', [ "SELECT *, strftime('%s',`starttime`) AS starttime_unix, strftime('%s',`endtime`) AS endtime_unix from $SESSIONS_TABLE where sessionid=?", {}, $session_id ] );
}

sub get_starttime_unix {
    my ( $self, $session_id ) = @_;

    my $row = $self->master_sql( 'selectrow_hashref', [ "SELECT strftime('%s',`starttime`) AS starttime_unix from $SESSIONS_TABLE where sessionid=?", {}, $session_id ] );

    if ( ref $row ) {
        return $row->{'starttime_unix'};
    }

    return;
}

sub get_endtime_unix {
    my ( $self, $session_id ) = @_;

    my $row = $self->master_sql( 'selectrow_hashref', [ "SELECT strftime('%s',`endtime`) AS endtime_unix from $SESSIONS_TABLE where sessionid=?", {}, $session_id ] );
    if ( ref $row ) {
        return $row->{'endtime_unix'};
    }

    return;
}

sub initiator {
    my ( $self, $session_id ) = @_;

    die Cpanel::Carp::safe_longmess("initiator requires a session_id") if !$session_id;

    return $self->get_session_details($session_id)->{'initiator'};
}

sub creator {
    my ( $self, $session_id ) = @_;

    die Cpanel::Carp::safe_longmess("creator requires a session_id") if !$session_id;

    return $self->get_session_details($session_id)->{'creator'};
}

sub _get_session_pid {
    my ( $self, $session_id ) = @_;

    my $quoted_session_id = $self->quote($session_id);

    my $row = $self->master_sql( 'selectrow_arrayref', ["SELECT pid from $SESSIONS_TABLE where sessionid=$quoted_session_id /* _get_session_pid */;"] );

    return $row->[0] if $row && ref $row;
    return;
}

sub _set_session_pid {
    my ( $self, $session_id, $pid ) = @_;

    my $quoted_session_id = $self->quote($session_id);
    my $quoted_pid        = $self->quote($pid);

    return $self->master_do("UPDATE $SESSIONS_TABLE set pid=$quoted_pid where sessionid=$quoted_session_id;");

}

sub _get_session_state_name {
    my ( $self, $session_id ) = @_;

    my $state_id = $self->_get_session_state($session_id);

    return $Whostmgr::Transfers::SessionBase::SESSION_STATE_NAMES{$state_id};
}

sub _get_session_state {
    my ( $self, $session_id ) = @_;

    my $quoted_session_id = $self->quote($session_id);

    my $row = $self->master_sql( 'selectrow_arrayref', ["SELECT state from $SESSIONS_TABLE where sessionid=$quoted_session_id /* _get_session_state */;"] );
    return $row->[0] if $row && ref $row;
    return;
}

sub _delete_session {
    my ( $self, $session_id ) = @_;

    $self->drop_session_db($session_id);
    my $quoted_session_id = $self->quote($session_id);
    eval { $self->master_do("DELETE FROM $SESSIONS_TABLE where sessionid=$quoted_session_id"); };
    return if $@;

    return 1;
}

sub _set_session_state {
    my ( $self, $session_id, $state ) = @_;
    my $quoted_session_id    = $self->quote($session_id);
    my $quoted_session_state = $self->quote($state);
    if ( $state == $SESSION_STATES{'COMPLETED'} || $state == $SESSION_STATES{'FAILED'} ) {
        return $self->master_do("UPDATE $SESSIONS_TABLE set state=$quoted_session_state,endtime=datetime() where sessionid=$quoted_session_id;");
    }
    else {
        return $self->master_do("UPDATE $SESSIONS_TABLE set state=$quoted_session_state where sessionid=$quoted_session_id;");
    }
}

sub _session_exists {
    my ( $self, $session_id ) = @_;
    $session_id =~ s{/}{}g;
    return -e ( $Whostmgr::Transfers::Session::Config::SESSION_DIR . '/' . $session_id ) ? 1 : 0;
}

1;
