package Cpanel::Server::WebSocket::cpanel::LogStreamer;

# cpanel - Cpanel/Server/WebSocket/cpanel/LogStreamer.pm
#                                                  Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Server::WebSocket::cpanel::LogStreamer

=head1 SYNOPSIS

See the documentation in L<Cpanel::Server::Handlers::WebSocket>.

=head1 DESCRIPTION

This module streams a log file being generated by a program you wish to
optionally follow.

Differs from PluginLog by being a bit more flexible regarding what you
might want to stream from it (and the format of the data you want in return).

It expects the following C<$ENV{'QUERY_STRING'}> with HTML query
parameters:

=over

=item * C<log_entry> - Required. The log entry to stream.

=item * C<pid> - Optional. If given, this module will monitor the log file
for updates until the indicated process is finished. If not given, the
file’s contents will be read once, then the connection will be closed.

=back

=cut

use parent qw( Cpanel::Server::WebSocket::cpanel );

#use constant _ACCEPTED_ACLS => qw{all};

use Net::WebSocket::Frame::text  ();
use Net::WebSocket::Frame::close ();

use Try::Tiny;

use Cpanel::Alarm                      ();
use Cpanel::Exception                  ();
use Cpanel::FHUtils::Blocking          ();
use Cpanel::Finally                    ();
use Cpanel::Inotify                    ();
use Cpanel::LoadFile::ReadFast         ();
use Cpanel::Log::MetaFormat            ();
use Cpanel::ProcessLog::WithChildError ();

use Cpanel::Exception ();
use Cpanel::Form      ();

use constant PROGRESS_EVENTS    => 'MODIFY';
use constant FINISH_EVENTS      => 'CLOSE_WRITE';
use constant GONE_EVENTS        => qw( DELETE_SELF MOVE_SELF );
use constant _ACCEPTED_FEATURES => ('sitejet');

#This shouldn’t take longer than an hour.
use constant TIMEOUT => 3600;

*_read = *Cpanel::LoadFile::ReadFast::read_all_fast;

=head1 METHODS

=head2 I<OBJ>->new()

As described in L<Cpanel::Server::Handlers::WebSocket>.

=cut

sub new {
    my ($class) = @_;

    my $self = bless {}, $class;

    my $form_hr = Cpanel::Form::parseform();
    my $user    = $form_hr->{'user'} || die 'Need user entry "user"';
    my $homedir = $Cpanel::homedir   || do { require Cpanel::PwCache; Cpanel::PwCache::gethomedir($user) };

    local $Cpanel::ProcessLog::WithChildError::DIR = "$homedir/logs/sitejet";
    my $log_prefix = $Cpanel::ProcessLog::WithChildError::DIR;
    my $log_entry  = $form_hr->{'log_entry'} || die 'Need query “log_entry”';

    @{$self}{qw( _log_entry  _pid  _rfh )} = (
        $log_entry,
        $form_hr->{'pid'},
        Cpanel::ProcessLog::WithChildError->open($log_entry),
    );

    $self->{'_start_size'} = -s $self->{'_rfh'};
    $self->{'_DIR'}        = $Cpanel::ProcessLog::WithChildError::DIR;

    return $self;
}

=head2 I<OBJ>->run()

As described in L<Cpanel::Server::Handlers::WebSocket>.

=cut

sub run {
    my ( $self, $courier ) = @_;

    local $self->{'_courier'} = $courier;
    local $Cpanel::ProcessLog::WithChildError::DIR = $self->{'_DIR'};

    try {
        $self->__do_interactive($courier);
    }
    catch {
        $courier->finish(
            'INTERNAL_ERROR',
            substr( Cpanel::Exception::get_string($_), 0, 120 ),
        );

        local $@ = $_;
        die;
    };

    return;
}

sub __do_interactive {
    my ( $self, $courier ) = @_;

    my ( %progress_events, %finish_events, %gone_events );

    @progress_events{ PROGRESS_EVENTS() } = ();
    @finish_events{ FINISH_EVENTS() }     = ();
    @gone_events{ GONE_EVENTS() }         = ();

    my $buf = q<>;

    my $infy           = Cpanel::Inotify->new();
    my $metadata_watch = Cpanel::ProcessLog::WithChildError->inotify_add_metadata(
        $self->{'_log_entry'},
        $infy,
        flags => [
            'CREATE',
            'MOVED_TO',
            'ONLYDIR',
            'DONT_FOLLOW',
        ],
    );

    my $log_watch = Cpanel::ProcessLog::WithChildError->inotify_add_log(
        $self->{'_log_entry'},
        $infy,
        flags => [
            PROGRESS_EVENTS(),
            GONE_EVENTS(),
        ],
    );

    if ( $self->{'_start_size'} ) {
        _read( $self->{'_rfh'}, $buf );
        $self->_send_log($buf) if length $buf;
        $buf = q<>;
    }

    my $is_blocking = Cpanel::FHUtils::Blocking::is_set_to_block( $self->{'_rfh'} );
    my $restore_non_blocking;
    if ( !$is_blocking ) {
        Cpanel::FHUtils::Blocking::set_blocking( $self->{'_rfh'} );

        $restore_non_blocking = Cpanel::Finally->new(
            sub {
                Cpanel::FHUtils::Blocking::set_non_blocking( $self->{'_rfh'} );
            }
        );
    }

    local $@;

    my ( $pid_is_gone, $ws_closed );

    $pid_is_gone = !$self->_pid_lives();

    local $SIG{'ALRM'} = sub {
        die( bless [], 'cgi::live_tail_file::POLL_TIMEOUT' );
    };

  INOTIFY_POLL:
    while (1) {

        #There’s no point to polling Inotify if the process is gone.
        if ( !$pid_is_gone ) {
            my $alarm = Cpanel::Alarm->new(1);
            my @events;

            eval { @events = $infy->poll(); 1 } or do {
                die if 'cgi::live_tail_file::POLL_TIMEOUT' ne ref $@;
            };

            #To be sure we’ve gotten everything:
            #1) After each poll timeout, check the PID. If it’s alive, repeat.
            #2) If it’s dead, then set $pid_is_gone, and repeat.
            #3) On the next poll timeout, we’re done.
            if ( !@events ) {
                last INOTIFY_POLL if $pid_is_gone;

                if ( !$self->_pid_lives() ) {
                    $pid_is_gone = 1;
                }

                next INOTIFY_POLL;
            }

            for my $evt (@events) {
                if ( $evt->{'wd'} eq $metadata_watch ) {
                    next if $evt->{'name'} ne 'CHILD_ERROR';

                    my $md_hr = Cpanel::ProcessLog::WithChildError->get_metadata( $self->{'_log_entry'} );
                    if ( $md_hr->{'CHILD_ERROR'} !~ tr<0-9><>c ) {

                        #No last() here because we still need to read()!
                        $pid_is_gone = 1;
                    }
                }
            }

            my @log_events = grep { $_->{'wd'} eq $log_watch } @events;

            my %uniq_events;
            @uniq_events{ map { @{ $_->{'flags'} } } @log_events } = ();

            if ( my @bad = grep { exists $gone_events{$_} } keys %uniq_events ) {
                @bad = sort @bad;
                $courier->finish(
                    'INTERNAL_ERROR',
                    "File went away! (@bad)",
                );
                $ws_closed = 1;

                #Let’s still try to read one more time.
                $pid_is_gone = 1;
            }

            if ( my @finish = grep { exists $finish_events{$_} } keys %uniq_events ) {
                @finish = sort @finish;

                #The process that was writing to the file
                #has closed the filehandle. Now we read one more time
                #to be sure we’ve gotten everything, then we’re done.
                $pid_is_gone = 1;
            }
        }

        #Finish reading the rest.
        _read( $self->{'_rfh'}, $buf );

        if ( length $buf ) {
            $self->_send_log($buf);
            $buf = q<>;
        }

        last INOTIFY_POLL if $pid_is_gone;
    }

    if ( !$ws_closed ) {
        my $metadata_hr = Cpanel::ProcessLog::WithChildError->get_metadata( $self->{'_log_entry'} );
        for my $k ( keys %$metadata_hr ) {
            $self->_send_text(
                Cpanel::Log::MetaFormat::encode_metadata( $k => $metadata_hr->{$k} ),
            );
        }

        {
            # Socket is closed but Cpanel/Server/WebSocket/Courier.pm throws
            # IO::Framed::X::ReadError in CloudLinux.
            # suppressing the noise in logs.
            local $SIG{'__WARN__'} = sub { };
            $courier->finish('SUCCESS');
        }
    }

    return;
}

sub _pid_lives {
    my ($self) = @_;

    return $self->{'_pid'} && kill 'ZERO', $self->{'_pid'};
}

sub _send_text {
    my ($self) = @_;    # $_[1] = payload

    $self->{'_courier'}->enqueue_send( 'text', $_[1] );
    $self->{'_courier'}->flush_write_queue();

    return;
}

sub _send_log {
    Cpanel::Log::MetaFormat::encode_log( $_[1] );
    return $_[0]->_send_text( $_[1] );
}

1;
