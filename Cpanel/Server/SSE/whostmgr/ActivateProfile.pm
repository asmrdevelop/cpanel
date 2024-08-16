package Cpanel::Server::SSE::whostmgr::ActivateProfile;

# cpanel - Cpanel/Server/SSE/whostmgr/ActivateProfile.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::SSE::whostmgr::ActivateProfile

=head1 SYNOPSIS

    # This would normally be set by cpsrvd based on the browser’s
    # request, not directly in code.
    local $ENV{'QUERY_STRING'} = 'log_id=2345.67864.987864';

    my $sse = Cpanel::Server::SSE::whostmgr::ActivateProfile->new(
        responder => $responder,
    );
    $sse->run();

=head1 DESCRIPTION

An SSE module for streaming the logs of WHM server profile changes.

=cut

use parent qw( Cpanel::Server::SSE::whostmgr );

use Try::Tiny;

use Cpanel::Exception         ();
use Cpanel::Form              ();
use Cpanel::Inotify           ();
use Cpanel::JSON              ();
use Cpanel::Server::Type::Log ();    ## PPI USE OK - used dynamically
use Cpanel::UPID              ();

use constant {
    _ENOENT => 2,
    _EINTR  => 4,
};

our $_LOG_CLASS = 'Cpanel::Server::Type::Log';

sub _init {
    my ($self) = @_;

    my $form_hr = Cpanel::Form::parseform();

    my $log_id = $form_hr->{'log_id'} or do {
        die Cpanel::Exception::create( 'cpsrvd::BadRequest', 'Provide “[_1]”.', ['log_id'] );
    };

    if ( $log_id =~ tr</><> ) {
        die Cpanel::Exception::create( 'cpsrvd::BadRequest', '“[_1]” is not a valid profile activation log ID.', [$log_id] );
    }

    my $rfh;
    try {
        $rfh = $_LOG_CLASS->open($log_id);
    }
    catch {
        if ( $_->error_name() eq 'ENOENT' ) {
            die Cpanel::Exception::create( 'cpsrvd::BadRequest', 'No profile activation log with ID “[_1]” exists on this system.', [$log_id] );
        }

        local $@ = $_;
        die;
    };

    $self->{'_log_pos'} = 0;

    if ( my $last_id = $self->_get_last_event_id() ) {
        if ( sysseek $rfh, $last_id, 1 ) {
            $self->{'_log_pos'} += $last_id;
        }
        else {
            warn "$self (log ID $log_id) seek($last_id): $!";
        }
    }

    $rfh->blocking(0);

    $self->{'_rfh'}    = $rfh;
    $self->{'_log_id'} = $log_id;

    return $self;
}

sub _read_and_report {
    my ($self) = @_;

    while ( sysread( $self->{'_rfh'}, my $buf, 65536 ) ) {
        $self->{'_log_pos'} += length $buf;

        $self->_send_sse_message(
            id    => $self->{'_log_pos'},
            event => 'message',
            data  => Cpanel::JSON::Dump($buf),
        );
    }

    die "read log “$self->{'_log_id'}”: $!" if $!;

    return;
}

sub _run {
    my ($self) = @_;

    my $rfh = $self->{'_rfh'};

    my $log_id = $self->{'_log_id'};

    my $inotify = Cpanel::Inotify->new();
    $_LOG_CLASS->inotify_add_log(
        $log_id,
        $inotify,
        flags => [ 'MODIFY', 'CLOSE_WRITE' ],
    );

    $self->_read_and_report();

    my $upid = $log_id;

    my $rin = q<>;
    vec( $rin, $inotify->fileno(), 1 ) = 1;

  READ_LOOP:
    while ( Cpanel::UPID::is_alive($upid) ) {

        # epoll would probably be overkill here …
        my $got = select( my $rout = $rin, undef, undef, 30 );

        if ( $got == 1 ) {
            for my $event ( $inotify->poll() ) {
                if ( grep { $_ eq 'MODIFY' } @{ $event->{'flags'} } ) {
                    $self->_read_and_report();
                }

                # If the writer closed  the file, then assume we are done.
                if ( grep { $_ eq 'CLOSE_WRITE' } @{ $event->{'flags'} } ) {
                    last READ_LOOP;
                }
            }
        }
        elsif ( $got == 0 ) {
            $self->_send_sse_heartbeat();
        }
        elsif ( $! != _EINTR() ) {
            warn "select(): $!";
        }
    }

    $self->_send_sse_message(
        event => 'finish',
        data  => Cpanel::JSON::Dump( $_LOG_CLASS->get_metadata($upid) ),
    );

    close $self->{'_rfh'};

    return;
}

1;
