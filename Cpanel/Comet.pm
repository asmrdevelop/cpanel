package Cpanel::Comet;

# cpanel - Cpanel/Comet.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=head1 Summary

This is the comet backend for cpsrvd

=head1 Usage

my $comet = Cpanel::Comet->new();
my $ok = $comet->subscribe('/some/channel');
my ($ok,$msg) = $comet->add_message('/some/channel','test message');
my $data = $comet->feed();
>> $VAR1 = [
>>          'test message'
>>        ];
print Dumper($data);
my ($ok,$msg) = $comet->add_message('/some/channel','test message 2');
my $data = $comet->feed();
>> $VAR1 = [
>>          'test message 2'
>>        ];

print Dumper($data);
....

=head1 Storage Backend Design

COMETROOT/subscriptions
    Directory containing a directory for each clientId

COMETROOT/subscriptions/eqoXvDYG2RWZhqYK
    Example clientId

COMETROOT/subscriptions/eqoXvDYG2RWZhqYK/%2fsome%2fchannel
    Example clientId subscribed to channel /some/channel (channels are uri encoded)

COMETROOT/subscriptions/eqoXvDYG2RWZhqYK/%2fsome%2fchannel/position
    The position the clientId is currently at in the channel feed

COMETROOT/subscriptions/eqoXvDYG2RWZhqYK/%2fsome%2fchannel/Sixz9LkLjWVR6Qpj
    A message id that has already been sent to the client.  We track all the message ids sent so we never send the same one twice
    This may be overkill

COMETROOT/channels
    Directory containing all the channels available

COMETROOT/channels/%2fsome%2fchannel
    Directory containing data for a specific channel

COMETROOT/channels/%2fsome%2fchannel/messages
    Directory containing all the messages send to the channel

COMETROOT/channels/%2fsome%2fchannel/messages/sN5kQMs7jdW3AQTk
    An Example message sent to the channel

COMETROOT/channels/%2fsome%2fchannel/feed
    Directory that contains the feeds for the current channel

COMETROOT/channels/%2fsome%2fchannel/feed/[0-999999...]
    Feed files for the channel.  The highest number contains the newest data.

=cut

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use Cpanel::Fcntl::Constants ();
use Cpanel::LoadFile         ();
use Cpanel::PwCache          ();
use Cpanel::Rand::Get        ();
use Cpanel::Encoder::URI     ();
use Cpanel::Inotify::Wrap    ();
use Cpanel::SV               ();

use constant WRONLY_CREAT_EXCL => $Cpanel::Fcntl::Constants::O_WRONLY | $Cpanel::Fcntl::Constants::O_CREAT | $Cpanel::Fcntl::Constants::O_EXCL;

my $MAX_FEED_SEARCH_ATTEMPTS = 30;
our $DEFAULT_BLOCK_TIMEOUT = 50000;
our $MAX_FEED_SIZE         = ( 256 * 1024 );    #256k
my $INOTIFY_ALARM_TRICK_FILE;

sub new {
    my ( $class, %OPTS ) = @_;

    my $self = bless {}, $class;

    if ( $Cpanel::CPDATA{'DEMO'} ) {
        die "Comet feeds are not available to Demo users.";
    }

    my $user = $self->_get_user();

    if ( !( $self->{'homedir'} = $OPTS{'homedir'} ) ) {
        $self->{'homedir'} = ( Cpanel::PwCache::getpwuid($>) )[7];
        Cpanel::SV::untaint( $self->{'homedir'} );
    }
    die "Homedir is required for Cpanel::Comet" if !$self->{'homedir'};
    $self->{'basedir'} = $self->{'homedir'} . '/.cpanel/comet/' . $user;
    Cpanel::SV::untaint( $self->{'basedir'} );
    $self->_create_clientid( $OPTS{'clientId'} );

    if ( !$self->{'clientId'} ) {
        die "Panic: failed to create a clientId";
    }

    $self->{'subscriptions'}            = {};
    $self->{'subscriptionsdir'}         = $self->{'basedir'} . '/subscriptions/' . $self->{'clientId'};
    $self->{'subscriptions_file'}       = $self->{'basedir'} . '/subscriptions/' . $self->{'clientId'} . '.subscriptions';
    $self->{'channels'}                 = {};
    $self->{'timeout'}                  = $OPTS{'timeout'} if $OPTS{'timeout'};
    $self->{'current_writeable_feed'}   = '';
    $self->{'current_channel_feed_dir'} = '';

    $self->{'DEBUG'} = $OPTS{'DEBUG'} if ( exists $OPTS{'DEBUG'} );

    #$self->{'DEBUG'} = 1;

    if ( !-e $self->{'subscriptions_file'} && open( my $sub_fh, '>>', $self->{'subscriptions_file'} ) ) {
        syswrite( $sub_fh, '1' );
    }

    $self->_reload_subscriptions_from_disk();
    return $self;
}

sub _init_inotify {
    my $self = shift;

    Cpanel::Inotify::Wrap::load();

    if ( $INC{'Linux/Inotify2.pm'} ) {
        if ( $self->{'inotify'} = Linux::Inotify2->new() ) {
            $self->{'inotify'}->blocking(1);
            $INOTIFY_ALARM_TRICK_FILE = $self->{'basedir'} . '/inotify_alarm_trick_' . $$;
            if ( !-e $INOTIFY_ALARM_TRICK_FILE ) {
                if ( open( my $fh, '>>', $INOTIFY_ALARM_TRICK_FILE ) ) {
                    close($fh);
                }
            }
            $self->{'inotify_alarm_trick_handle'} = $self->{'inotify'}->watch( $INOTIFY_ALARM_TRICK_FILE, &Linux::Inotify2::IN_MODIFY )
              or do {
                syswrite( STDERR, "$$: [new] Could not invoke inotify on: $INOTIFY_ALARM_TRICK_FILE: $!\n" );
                delete $self->{'inotify'};
              };
            syswrite( STDERR, "$$: [new] Setup inotify on $INOTIFY_ALARM_TRICK_FILE\n" ) if $self->{'DEBUG'};
        }
        else {
            syswrite( STDERR, "$$: [new] Could not init inotify: $!\n" );
            delete $self->{'inotify'};
        }
    }
    else {
        syswrite( STDERR, "$$: [new] inotify not available: $!\n" ) if $self->{'DEBUG'};
    }

    syswrite( STDERR, "$$: [new] inotify=" . ( scalar ref $self->{'inotify'} ) . "\n" ) if $self->{'DEBUG'};

    if ( $self->{'inotify'} ) {
        ( $self->{'inotify_subscriptions_file_handle'} = $self->{'inotify'}->watch( $self->{'subscriptions_file'}, &Linux::Inotify2::IN_MODIFY ) ) or do {
            syswrite( STDERR, "$$: [new] Could not invoke inotify on: $self->{'subscriptions_file'}: $!\n" );
            delete $self->{'inotify'};
        };
        syswrite( STDERR, "$$: [new] Setup inotify on $self->{'subscriptions_file'}\n" ) if $self->{'DEBUG'} && $self->{'inotify'};
    }

    syswrite( STDERR, "$$: [new] inotify=" . ( scalar ref $self->{'inotify'} ) . "\n" ) if $self->{'DEBUG'};

    $self->{'inotify_inited'} = 1;
}

sub _reload_subscriptions_from_disk {
    my $self = shift;

    syswrite( STDERR, "$$: [_reload_subscriptions_from_disk] SIZE=" . ( defined $self->{'subscriptions_size'} ? $self->{'subscriptions_size'} : "undef" ) . "\n" ) if $self->{'DEBUG'};

    if ( opendir( my $sub_dir_fh, $self->{'subscriptionsdir'} ) ) {
        $self->{'subscriptions_size'} = ( stat( $self->{'subscriptions_file'} ) )[7];
        $self->{'subscriptions'}      = { map { ( $_ =~ tr/\%// ? Cpanel::Encoder::URI::uri_decode_str($_) : $_ ) => undef } grep ( !/^\./, readdir($sub_dir_fh) ) };
        closedir($sub_dir_fh);
        return 1;
    }
    else {
        syswrite( STDERR, "$$: Cpanel::Comet::_reload_subscriptions_from_disk() Critical: Failed to load subscriptions for clientId $self->{'clientId'}: $!\n" );
        return 0;
    }
}

sub add_message {
    my ( $self, $channel, $data, $messageid ) = @_;
    my $safe_channel = Cpanel::Encoder::URI::uri_encode_str($channel);
    Cpanel::SV::untaint($safe_channel);    # safe because it is uri encoded
    $messageid ||= Cpanel::Rand::Get::getranddata(16);
    my $msg_safe = 0;
    while ( -e $self->{'basedir'} . '/channels/' . $safe_channel . '/messages/' . $messageid && ++$msg_safe < 1024 ) {
        $messageid = Cpanel::Rand::Get::getranddata(16);
    }
    $messageid =~ s!/!!g;
    Cpanel::SV::untaint($messageid);       # safe because it is generated or passed from trusted source

    if ( sysopen( my $fh, $self->{'basedir'} . '/channels/' . $safe_channel . '/messages/' . $messageid, WRONLY_CREAT_EXCL, 0600 ) ) {
        syswrite( $fh, $data );
        close($fh);
    }
    else {
        $self->_comet_ensure_dir( 'channels/' . $safe_channel . '/messages' );
        $self->_comet_ensure_dir( 'channels/' . $safe_channel . '/feed' );
        if ( sysopen( my $fh, $self->{'basedir'} . '/channels/' . $safe_channel . '/messages/' . $messageid, WRONLY_CREAT_EXCL, 0600 ) ) {
            syswrite( $fh, $data );
            close($fh);
        }
        else {
            return ( 0, "Failed to add message : $!" );
        }
    }

    my ( $current_feed_id, $current_feed, $previous_feed_needs_ping, $previous_feed ) = $self->_get_channel_activate_feed_id( $safe_channel, 1 );
    syswrite( STDERR, "$$: [add_message] found current feed to be $current_feed\n" ) if $self->{'DEBUG'};
    if ( $self->{'current_writeable_feed'} eq $current_feed || open( $self->{'current_writeable_feed_fh'}, '>>', $current_feed ) ) {
        $self->{'current_writeable_feed'} = $current_feed;
        syswrite( $self->{'current_writeable_feed_fh'}, $messageid . "\n" );
        syswrite( STDERR,                               "$$: [add_message] Message added to $current_feed_id ($current_feed) for $safe_channel\n" )
          if $self->{'DEBUG'};
        if ( $previous_feed_needs_ping && $previous_feed ) {
            syswrite( STDERR, "$$: [add_message] Attempt Ping previous feed $previous_feed\n" )
              if $self->{'DEBUG'};
            if ( open( my $fh, '>>', $previous_feed ) ) {
                syswrite( $fh, "\n" );
                close($fh);
                syswrite( STDERR, "$$: [add_message] Ping previous feed $previous_feed\n" )
                  if $self->{'DEBUG'};
            }
        }
        return ( 1, "Message added" );
    }
    return ( 0, "Failed to update feed: $!" );
}

sub feed {    ##no critic qw(ExcessComplexity) - needs scrum
    my $self          = shift;
    my $block         = shift;
    my $block_timeout = ( shift || $self->{'timeout'} || $DEFAULT_BLOCK_TIMEOUT ) / 1000 * 4;    #convert to 0.25 increments
    $block_timeout *= 1000 if ( $block_timeout < 1 );

    syswrite( STDERR, "$$: [feed] block timeout is $block_timeout (self-timeout = " . ( defined $self->{'timeout'} ? $self->{'timeout'} : "undef" ) . ") (block = " . ( $block ? "true" : "false" ) . ")\n" )
      if $self->{'DEBUG'};

    if ( !$self->{'clientId'} ) { return ( 0, 'clientId not initalized' ); }

    syswrite( STDERR, "$$: [feed] enter " . ( $block ? 'blocking' : 'non-blocking' ) . "\n" ) if $self->{'DEBUG'};

    $self->_init_inotify() if !$self->{'inotify_inited'};

    my @feed_messages;

    if ( $self->{'subscriptions_size'} != ( stat( $self->{'subscriptions_file'} ) )[7] ) {
        my $reload_ok = $self->_reload_subscriptions_from_disk();
        return if !$reload_ok;
    }

    my %real_channels =
      map { $_ => undef }
      map { $self->_resolve_subscription_to_channels($_) }
      keys %{ $self->{'subscriptions'} };

    syswrite( STDERR, "$$: [feed] real_channels = " . join( ' , ', keys %real_channels ) . "\n" )
      if $self->{'DEBUG'};

    foreach my $channel ( keys %real_channels ) {
        my ( $current_feed_id, $current_feed_position );
        my $safe_channel = Cpanel::Encoder::URI::uri_encode_str($channel);
        Cpanel::SV::untaint($safe_channel);    # safe -- this is uri encoded
        $self->{'channels'}{$channel} ||= {};
        $self->{'channels'}{$channel}{'safe_channel'} ||= $safe_channel;
        syswrite( STDERR, "$$: [feed] checking channel $safe_channel\n" ) if $self->{'DEBUG'};

        #FIXME: we really need to do one loop and resolve the globs, then loop again with all the channels we found:
        if (   ref $self->{'channels'}{$channel}
            && exists $self->{'channels'}{$channel}{'current_feed_id'}
            && $self->{'channels'}{$channel}{'current_feed_id'}
            && exists $self->{'channels'}{$channel}{'current_feed_position'}
            && defined $self->{'channels'}{$channel}{'current_feed_position'} ) {
            ( $current_feed_id, $current_feed_position ) = @{ $self->{'channels'}{$channel} }{ 'current_feed_id', 'current_feed_position' };
            syswrite( STDERR, "$$: [feed] Loading position and feed id from memory ($current_feed_id,$current_feed_position)\n" )
              if $self->{'DEBUG'};
        }
        else {
            my $position_file = $self->{'basedir'} . '/subscriber_channel_positions/' . $self->{'clientId'} . '/' . $safe_channel;
            if ( -e $position_file ) {
                my ( $attempts, $current_feed_position_data ) = (0);
                while ( ++$attempts < 5 && !$current_feed_position_data ) {    # we may be waiting on another process to open, write so we will try 10 times
                    $current_feed_position_data = Cpanel::LoadFile::loadfile( $position_file, { 'skip_exists_check' => 1 } );
                    if ( !$current_feed_position_data ) {
                        syswrite( STDERR, "$$: [feed] got and empty position file.. waiting for it to be populated\n" )
                          if $self->{'DEBUG'};
                        select( undef, undef, undef, 0.25 );
                    }
                }
                ( $current_feed_id, $current_feed_position ) =
                  split( /:/, $current_feed_position_data );
            }
            if ( !defined $current_feed_position ) {
                $self->_comet_ensure_dir( 'channels/' . $safe_channel . '/feed' );
                $self->_comet_ensure_dir( 'subscriber_channel_positions/' . $self->{'clientId'} );
                $self->_comet_ensure_dir( 'subscriptions/' . $self->{'clientId'} . '/' . $safe_channel );

                syswrite( STDERR, "$$: [feed] no feed history ($position_file), guessing feed position\n" )
                  if $self->{'DEBUG'};
                ($current_feed_id) = $self->_get_channel_activate_feed_id($safe_channel);
                $current_feed_position = 0;

            }
            else {
                syswrite( STDERR, "$$: [feed] history loaded from  ($position_file) -- $current_feed_id, $current_feed_position\n" )
                  if $self->{'DEBUG'};
            }
            if ( !-e $self->{'basedir'} . '/channels/' . $safe_channel . '/feed/' . $current_feed_id ) {
                if ( my $found_next_feed = $self->_find_next_feed( $safe_channel, $current_feed_id ) ) {
                    syswrite( STDERR, "$$: [feed] loading from positions file : reached end of feed , going to next feed $current_feed_id moves to " . ( $current_feed_id + $found_next_feed ) . " in $channel\n" )
                      if $self->{'DEBUG'};
                    $current_feed_id += $found_next_feed;
                    $current_feed_position = 0;
                }
            }

        }

        ($current_feed_id) = $current_feed_id =~ /(\d+)/;    # untaint - safe always a number
        my $feed_fh;

      READ_CHANNEL_FEEDS:
        while (
            ref $self->{'channels'}{$channel}{'fh'}
            ? ( $feed_fh = $self->{'channels'}{$channel}{'fh'} )
            : open( $feed_fh, '<', $self->{'basedir'} . '/channels/' . $safe_channel . '/feed/' . $current_feed_id )
        ) {
            syswrite( STDERR, "$$: [feed] reading from $safe_channel/feed/$current_feed_id @ $current_feed_position\n" )
              if $self->{'DEBUG'};
            if ( $current_feed_position == -1 ) {
                seek( $feed_fh, 0, 2 );    #SEEK_END
                $current_feed_position = $self->_systell($feed_fh);
                @{ $self->{'channels'}{$channel} }{ 'current_feed_id', 'current_feed_position' } = ( $current_feed_id, $current_feed_position );

                syswrite( STDERR, "$$: [feed] reading from $safe_channel/feed/$current_feed_id @ $current_feed_position (SEEK_END)\n" )
                  if $self->{'DEBUG'};

            }
            elsif ( $current_feed_position > 0 ) {
                seek( $feed_fh, $current_feed_position, 0 );    #SEEK_SET  -- buffered io may cause to to see to the wrong position?
                syswrite( STDERR, "$$: [feed] reading from $safe_channel/feed/$current_feed_id @ $current_feed_position (SEEK_SET)\n" )
                  if $self->{'DEBUG'};
            }

            if ( $current_feed_position >= $MAX_FEED_SIZE ) {
                if ( my $found_next_feed = $self->_find_next_feed( $safe_channel, $current_feed_id ) ) {
                    syswrite( STDERR, "$$: [feed] next feed_id : reached end of feed , going to next feed $current_feed_id moves to " . ( $current_feed_id + $found_next_feed ) . " in $channel\n" )
                      if $self->{'DEBUG'};
                    $current_feed_id += $found_next_feed;
                    $current_feed_position = 0;
                    $self->_move_channel_to_next_feed( $channel, $current_feed_id );
                    next;
                }
            }

            my $setup_inotify_watch = 0;

            if ($block) {
                @{ $self->{'channels'}{$channel} }{ 'fh', 'current_feed_id', 'current_feed_position' } = ( $feed_fh, $current_feed_id, $current_feed_position );
                if ( exists $self->{'inotify'}
                    && !ref $self->{'channels'}{$channel}{'inotify'} ) {
                    $setup_inotify_watch = 1;
                    $self->{'channels'}{$channel}{'inotify'} = $self->{'inotify'}->watch( $self->{'basedir'} . '/channels/' . $safe_channel . '/feed/' . $current_feed_id, &Linux::Inotify2::IN_MODIFY )
                      or do {
                        syswrite( STDERR, "$$: [feed] Could not invoke inotify for: $safe_channel/$current_feed_id (feed): $!\n" );
                        delete $self->{'inotify'};
                      };
                }
                syswrite( STDERR, "$$: [feed] Setup inotify on " . $self->{'basedir'} . '/channels/' . $safe_channel . '/feed/' . $current_feed_id . "\n" ) if $setup_inotify_watch && $self->{'DEBUG'};
            }

            # We must do a read if we setup_inotify_watch to prevent a race condition where the change happens before we set the inotify watch up

            if ( !$block || $setup_inotify_watch ) {
                my ( $events_read, $next_file ) = $self->_read_channel_feed( $feed_fh, $channel, $safe_channel, \$current_feed_id, \$current_feed_position, \@feed_messages, 1 );
                @{ $self->{'channels'}{$channel} }{'current_feed_position'} = ($current_feed_position) if !$next_file;
                if ($next_file) {
                    syswrite( STDERR, "$$: [feed] reading -next (next_file)\n" ) if $self->{'DEBUG'};
                    next READ_CHANNEL_FEEDS;
                }
                else {
                    syswrite( STDERR, "$$: [feed] reading -last (!next_file)\n" ) if $self->{'DEBUG'};
                    last READ_CHANNEL_FEEDS;
                }
            }
            else {
                last READ_CHANNEL_FEEDS;
            }
        }
        if ( !ref $feed_fh ) {
            Carp::confess("Could not start feeding channel $channel ($current_feed_id)");
        }
    }

    syswrite( STDERR, "$$: [feed] inotify=" . scalar ref( $self->{'inotify'} ) . "\n" ) if $self->{'DEBUG'};

    if ( $block && !@feed_messages ) {
        local $SIG{'ALRM'} = sub {
            if ( open( INOTIFY_ALARM_FH, '>', $INOTIFY_ALARM_TRICK_FILE ) ) {
                print INOTIFY_ALARM_FH 1;
                close(INOTIFY_ALARM_FH);
            }
            else {
                Carp::cluck("Fatal error while attempt to write inotify wake up file: $INOTIFY_ALARM_TRICK_FILE: $!");
            }
          }
          if exists $self->{'inotify'};    # local will not happen if this if if false

        my $set_alarm = 0;
        my $original_alarm_time;
        if ( exists $self->{'inotify'} ) {
            $set_alarm           = 1;
            $original_alarm_time = alarm( $block_timeout / 4 );
            syswrite( STDERR, "$$: [feed] setup inotify alarm: " . ( $block_timeout / 4 ) . "\n" ) if $self->{'DEBUG'};
        }
        my ( $timeout, $changed_files, $loop_count, $current_feed_id, $current_feed_position, $next_file, $channel_events_read, $events_read, $previous_loop_has_inotify_channel_feed_change, $subscriptions_file_updated );
      READ_LOOP:
        while ( $loop_count++ < $block_timeout ) {
            if ( exists $self->{'inotify'}
                && !$previous_loop_has_inotify_channel_feed_change ) {
                syswrite( STDERR, "$$: [feed] [blocking loop in inotify mode] $loop_count (" . join( ',', keys %{ $self->{'subscriptions'} } ) . ")]\n" )
                  if $self->{'DEBUG'};
                my @events = $self->{'inotify'}->read();
                syswrite( STDERR, "$$: [feed] got inotify events: " . scalar @events . "\n" )
                  if $self->{'DEBUG'};
              INOTIFY_EVENTS:
                foreach my $event (@events) {
                    my $file = $event->fullname();
                    if ( $file eq $self->{'subscriptions_file'} ) {
                        $subscriptions_file_updated = 1;
                        syswrite( STDERR, "$$: [feed] [subscriptions_file updated]\n" ) if $self->{'DEBUG'};
                        next;

                    }
                    syswrite( STDERR, "$$: [feed] detected notify event on $file\n" )
                      if $self->{'DEBUG'};
                    my ($safe_channel) = $file =~ m!channels/([^/]+)!;
                    if ( !$safe_channel ) {
                        syswrite( STDERR, "$$: [feed] INOTIFY TIMEOUT (read $file)\n" )
                          if $self->{'DEBUG'};
                        $timeout = 1;
                        last INOTIFY_EVENTS;
                    }
                    my $channel = Cpanel::Encoder::URI::uri_decode_str($safe_channel);
                    $current_feed_id = $self->{'channels'}{$channel}{'current_feed_id'};
                    syswrite( STDERR, "$$: [feed] INOTIFY READY CHANNEL --$channel-- ($self->{'channels'}{$channel}{'safe_channel'} (feed id:$current_feed_id)  $current_feed_position < " . ( stat( $self->{'channels'}{$channel}{'fh'} ) )[7] . ")\n" )
                      if $self->{'DEBUG'};
                    ( $channel_events_read, $next_file, $changed_files ) = $self->_read_channel_feed( $self->{'channels'}{$channel}{'fh'}, $channel, $self->{'channels'}{$channel}{'safe_channel'}, \$current_feed_id, \$current_feed_position, \@feed_messages, 1 );
                    $events_read += $channel_events_read;
                    if ($next_file) {
                        $previous_loop_has_inotify_channel_feed_change = 1;    # we have to stat the file because the file changed an our inotify watch is going to be watching the wrong file
                        syswrite( STDERR, "$$: [feed] previous_loop_has_inotify_channel_feed_change=1\n" ) if $self->{'DEBUG'};
                    }
                    else {
                        @{ $self->{'channels'}{$channel} }{'current_feed_position'} = ($current_feed_position);
                    }
                }
            }
            else {
                syswrite( STDERR, "$$: [feed] [blocking loop in stat mode] inotify=$self->{'inotify'} previous_loop_has_inotify_channel_feed_change=$previous_loop_has_inotify_channel_feed_change $loop_count (" . join( ',', keys %{ $self->{'subscriptions'} } ) . ")]\n" )
                  if $self->{'DEBUG'};
                $previous_loop_has_inotify_channel_feed_change = 0;
                foreach my $channel ( keys %real_channels ) {
                    my $current_channel_file_handle_position = ( stat( $self->{'channels'}{$channel}{'fh'} ) )[7];
                    syswrite( STDERR, "$$: [feed] [current_position] channel=$channel = position (size of file)=$self->{'channels'}{$channel}{'current_feed_position'} -- FH position: " . ( ( stat( $self->{'channels'}{$channel}{'fh'} ) )[7] ) . "\n" ) if $self->{'DEBUG'};
                    if ( !defined $current_channel_file_handle_position || $current_channel_file_handle_position > $self->{'channels'}{$channel}{'current_feed_position'} || $current_channel_file_handle_position > $MAX_FEED_SIZE ) {    #size of file has grown
                        $current_feed_id = $self->{'channels'}{$channel}{'current_feed_id'};
                        syswrite( STDERR, "$$: [feed] READY CHANNEL (channel:$self->{'channels'}{$channel}{'safe_channel'}) (feed id:$current_feed_id) (current_feed_position:$current_feed_position) < " . ( stat( $self->{'channels'}{$channel}{'fh'} ) )[7] . ")\n" )
                          if $self->{'DEBUG'};
                        ( $channel_events_read, $next_file, $changed_files ) = $self->_read_channel_feed( $self->{'channels'}{$channel}{'fh'}, $channel, $self->{'channels'}{$channel}{'safe_channel'}, \$current_feed_id, \$current_feed_position, \@feed_messages, 1 );
                        $events_read += $channel_events_read;
                        if ( !$next_file ) {
                            @{ $self->{'channels'}{$channel} }{'current_feed_position'} = ($current_feed_position);
                        }
                    }
                }
            }
            if ($changed_files) {
                $changed_files = 0;
                syswrite( STDERR, "$$: [feed] we have changed files\n" ) if $self->{'DEBUG'};
                next READ_LOOP;
            }
            elsif ( @feed_messages || $subscriptions_file_updated || $events_read || $timeout || ( !$self->{'inotify'} && $self->{'subscriptions_size'} != ( stat( $self->{'subscriptions_file'} ) )[7] ) ) {
                $events_read = 0;
                syswrite( STDERR, "$$: [feed] events_read: $events_read\n" ) if $self->{'DEBUG'};
                last READ_LOOP;
            }
            select( undef, undef, undef, 0.25 ) if !exists $self->{'inotfiy'};
        }

        alarm( $original_alarm_time ? $original_alarm_time : 0 ) if $set_alarm;
    }

    return \@feed_messages;
}

sub _move_channel_to_next_feed {
    my ( $self, $channel, $new_feed_id ) = @_;
    syswrite( STDERR, "$$: [_move_channel_to_next_feed] $channel (" . ( $new_feed_id - 1 ) . " => $new_feed_id)\n" )
      if $self->{'DEBUG'};
    my $safe_channel = $self->{'channels'}{$channel}{'safe_channel'} || Cpanel::SV::untaint( Cpanel::Encoder::URI::uri_encode_str($channel) );    # safe because it is uri encoded

    close( $self->{'channels'}{$channel}{'fh'} ) if $self->{'channels'}{$channel}{'fh'};
    delete $self->{'channels'}{$channel}{'fh'};
    $self->{'channels'}{$channel}{'inotify'}->cancel()
      if exists $self->{'channels'}{$channel}{'inotify'};
    delete $self->{'channels'}{$channel}{'inotify'};
    my $changed_files = 0;

    if ( open( my $feed_fh, '<', $self->{'basedir'} . '/channels/' . $safe_channel . '/feed/' . $new_feed_id ) ) {                                #_read_channel_feed incremented this
        $changed_files = 1;
        @{ $self->{'channels'}{$channel} }{ 'fh', 'current_feed_id', 'current_feed_position' } = ( $feed_fh, $new_feed_id, 0 );
        if ( exists $self->{'inotify'} ) {
            $self->{'channels'}{$channel}{'inotify'} = $self->{'inotify'}->watch( $self->{'basedir'} . '/channels/' . $safe_channel . '/feed/' . $new_feed_id, &Linux::Inotify2::IN_MODIFY )
              or do {
                syswrite( STDERR, "$$: [_move_channel_to_next_feed] Could not invoke inotify for: $safe_channel/$new_feed_id (feed): $!\n" );
                delete $self->{'inotify'};
              };
            syswrite( STDERR, "$$: [_move_channel_to_next_feed]: switched inotify to $safe_channel, $new_feed_id\n" )
              if $self->{'DEBUG'};
        }

        if ( $new_feed_id - 2 >= 1 ) {
            $self->_remove_feed( $safe_channel, $new_feed_id - 2 );
        }
    }
    else {
        syswrite( STDERR, "$$: [_move_channel_to_next_feed]: failed to move to new feed $new_feed_id in channel $channel: $!\n" )
          if $self->{'DEBUG'};

    }
    return $changed_files;
}

sub _remove_feed {
    my ( $self, $safe_channel, $feed ) = @_;

    my $feed_file = $self->{'basedir'} . '/channels/' . $safe_channel . '/feed/' . $feed;
    if ( open( my $fh, '<', $feed_file ) ) {
        $self->_safe_rm( $feed_file, map { chomp; m{^([^/.]+)$} && $self->{'basedir'} . '/channels/' . $safe_channel . '/messages/' . $1 || () } <$fh> );
        close $fh;
    }
}

sub subscribe {
    my $self = shift;

    if ( !$self->{'clientId'} ) { return ( 0, 'clientId not initalized' ); }

    my $sub      = shift;
    my $position = shift;

    if ( defined $position ) {
        syswrite( STDERR, "$$: [subscribe]: requested position is $position\n" ) if $self->{'DEBUG'};
    }

    my $safe_sub = Cpanel::Encoder::URI::uri_encode_str($sub);
    Cpanel::SV::untaint($safe_sub);    # safe uri encoded.

    my $subscription_dir = $self->{'subscriptionsdir'} . '/' . $safe_sub;
    $self->{'subscriptions'}->{$sub} = undef;

    syswrite( STDERR, "$$: [subscribe] making [$subscription_dir]\n" ) if $self->{'DEBUG'};
    if ( -e $subscription_dir || mkdir( $subscription_dir, 0700 ) ) {

        if ( open( my $sub_fh, '>>', $self->{'subscriptions_file'} ) ) {
            syswrite( $sub_fh, '1' );
        }

        my %real_channels =
          map { $_ => undef } $self->_resolve_subscription_to_channels($sub);
        syswrite( STDERR, "$$: [subscribe] real_channels = " . join( ' , ', keys %real_channels ) . "\n" )
          if $self->{'DEBUG'};

        foreach my $channel ( keys %real_channels ) {
            my $safe_channel = Cpanel::Encoder::URI::uri_encode_str($channel);
            next if !$safe_channel;
            $self->_comet_ensure_dir( 'channels/' . $safe_channel . '/feed' );
            $self->_comet_ensure_dir( 'subscriber_channel_positions/' . $self->{'clientId'} );
            $self->_comet_ensure_dir( 'subscriptions/' . $self->{'clientId'} . '/' . $safe_channel );

            if ( sysopen( my $position_fh, $self->{'basedir'} . '/subscriber_channel_positions/' . $self->{'clientId'} . '/' . $safe_channel, WRONLY_CREAT_EXCL, 0600 ) ) {
                my ( $current_feed_id, $current_feed ) = $self->_get_channel_activate_feed_id($safe_channel);
                if ( !-e $current_feed && open( my $fh, '>>', $current_feed ) ) {
                    close($fh);
                }
                my $current_feed_position = defined $position ? $position : ( ( stat( $self->{'basedir'} . '/channels/' . $safe_channel . '/feed/' . $current_feed_id ) )[7] || 0 );
                @{ $self->{'channels'}{$channel} }{ 'current_feed_id', 'current_feed_position' } = ( $current_feed_id, $current_feed_position );
                syswrite( STDERR, "$$: [subscribe] wrote initial position for $channel : feed_id=$current_feed_id feed_position=$current_feed_position\n" )
                  if $self->{'DEBUG'};
                syswrite( $position_fh, $current_feed_id . ':' . $current_feed_position );
                close($position_fh);
            }
        }
        return 1;
    }
    else {
        return 0;
    }
}

sub purgeclient {
    my ($self) = @_;
    if ( !$self->{'clientId'} ) { return ( 0, 'clientId not initalized' ); }
    $self->_safe_rm( $self->{'basedir'} . '/subscriber_channel_positions/' . $self->{'clientId'}, $self->{'subscriptionsdir'}, $self->{'subscriptions_file'} );
    return 1;
}

sub _safe_rm {
    my ( $self, @kill_paths ) = @_;
    my @ok_to_kill = grep { m#^$self->{'basedir'}/# } @kill_paths;
    require File::Path;
    foreach my $path (@ok_to_kill) {
        local $@;
        eval { File::Path::rmtree($path); };
        warn if $@;
    }
    return 1;
}

sub destroy_channel {
    my ( $self, $channel ) = @_;
    my $safe_channel = Cpanel::Encoder::URI::uri_encode_str($channel);
    return 0 if !$safe_channel;
    $safe_channel =~ s/\///g;
    $self->_safe_rm( $self->{'basedir'} . '/channels/' . $safe_channel );
    return 1;
}

sub unsubscribe {
    my ( $self, $sub ) = @_;

    if ( !$self->{'clientId'} ) { return ( 0, 'clientId not initalized' ); }

    return ( 0, "Subscription to unsubscribe is required" ) if !$sub;

    my $safe_sub = Cpanel::SV::untaint( Cpanel::Encoder::URI::uri_encode_str($sub) );

    if ( open( my $sub_fh, '>>', $self->{'subscriptions_file'} ) ) {
        syswrite( $sub_fh, '0' );
    }

    if ( !exists $self->{'subscriptions'}->{$sub} ) {
        $self->_reload_subscriptions_from_disk();
    }
    if ( !exists $self->{'subscriptions'}->{$sub} ) {
        return 0;
    }
    my %real_channels =
      map { $_ => undef } $self->_resolve_subscription_to_channels($sub);
    syswrite( STDERR, "$$: [unsubscribe] real_channels = " . join( ' , ', keys %real_channels ) . "\n" )
      if $self->{'DEBUG'};

    my @kill;

    foreach my $channel ( keys %real_channels ) {
        my $safe_channel = Cpanel::Encoder::URI::uri_encode_str($channel);
        next if !$safe_channel;
        push @kill, $self->{'basedir'} . '/subscriber_channel_positions/' . $self->{'clientId'} . '/' . $safe_channel, $self->{'subscriptionsdir'} . '/' . $safe_channel;
    }

    $self->_safe_rm( @kill, $self->{'subscriptionsdir'} . '/' . $sub );

    delete $self->{'subscriptions'}->{$sub};
    return 1;

}

sub _systell {
    my ( $self, $fh ) = @_;
    return sysseek( $fh, 0, 1 );
}

sub _resolve_subscription_to_channels {
    my $self         = shift;
    my $sub          = shift;
    my $all_channels = shift;

    syswrite( STDERR, "$$: [_resolve_subscription_to_channels] sub = $sub\n" )
      if $self->{'DEBUG'};

    if ( $sub =~ tr/*// ) {
        syswrite( STDERR, "$$: [_resolve_subscription_to_channels] Wildcard handler\n" )
          if $self->{'DEBUG'};
        if ( !scalar keys %$all_channels ) {
            if ( opendir( my $sub_dir_fh, $self->{'basedir'} . '/channels' ) ) {
                $all_channels = { map { ( $_ =~ tr/\%// ? Cpanel::Encoder::URI::uri_decode_str($_) : $_ ) => undef } grep ( !/^\./, readdir $sub_dir_fh ) };
                closedir($sub_dir_fh);
            }
        }

        syswrite( STDERR, "$$: [_resolve_subscription_to_channels] all_channels = " . join( ' , ', keys %$all_channels ) . "\n" )
          if $self->{'DEBUG'};
        my $sub_regex;
        if ( exists $self->{'sub_regex_cache'}{$sub} ) {
            $sub_regex = $self->{'sub_regex_cache'}{$sub};
        }
        else {
            my $escaped_sub = quotemeta($sub);
            syswrite( STDERR, "$$: [_resolve_subscription_to_channels] escaped sub before wildcard translation = [$escaped_sub]\n" )
              if $self->{'DEBUG'};
            if ( $escaped_sub !~ s/\\\*\\\*/\.\*/g ) {
                $escaped_sub =~ s/\\\*/\[\^\\\/]\+/g;
            }
            syswrite( STDERR, "$$: [_resolve_subscription_to_channels] calculated regex = $escaped_sub\n" )
              if $self->{'DEBUG'};
            $self->{'sub_regex_cache'}{$sub} = $sub_regex = eval { qr/^$escaped_sub/; };
        }
        syswrite( STDERR, "$$: [_resolve_subscription_to_channels] sub_regex = $sub_regex\n" )
          if $self->{'DEBUG'};
        if ($sub_regex) {
            return grep ( /$sub_regex/, keys %$all_channels );
        }
    }
    else {
        return ($sub);

    }
}

sub _read_channel_feed {    ##no critic qw(ProhibitManyArgs) - needs refactor
    my ( $self, $feed_fh, $channel, $safe_channel, $current_feed_id_ref, $current_feed_position_ref, $feed_messages_ref, $leaveopen ) = @_;
    if ( !$feed_fh ) { Carp::confess("Could not read $channel $$current_feed_id_ref"); }
    syswrite( STDERR, "$$: [_read_channel_feed] args = ( $feed_fh, $channel, $safe_channel, $current_feed_id_ref, $current_feed_position_ref, $feed_messages_ref, $leaveopen )\n" ) if $self->{'DEBUG'};
    my $events_read = 0;
    my $fh_read     = 0;
    while ( my $messageid = readline($feed_fh) ) {
        $fh_read = 1;
        ($messageid) = $messageid =~ m!([^/]+)!;    # untaint -- safe read from trusted file
        chomp($messageid);
        next if ( $messageid eq '' );
        syswrite( STDERR, "$$: [feed] $self->{'clientId'} read $messageid from feed $$current_feed_id_ref for $safe_channel\n" )
          if $self->{'DEBUG'};
        if ( sysopen( my $fh, $self->{'subscriptionsdir'} . '/' . $safe_channel . '/' . $messageid, WRONLY_CREAT_EXCL, 0600 ) ) {
            $events_read++;
            push @$feed_messages_ref, Cpanel::LoadFile::loadfile( $self->{'basedir'} . '/channels/' . $safe_channel . '/messages/' . $messageid, { 'skip_exists_check' => 1 } );
            close($fh);
        }
        else {
            syswrite( STDERR, "$$: [feed] $self->{'clientId'} already received $messageid -- not sending (" . $self->{'subscriptionsdir'} . '/' . $safe_channel . '/' . $messageid . " exists )\n" )
              if $self->{'DEBUG'};
        }
    }

    my $new_feed_position = $fh_read ? $self->_systell($feed_fh) : $$current_feed_position_ref;

    # If we read some messages we need to update the position file
    if ( $new_feed_position != $$current_feed_position_ref ) {
        if ( open( my $position_fh, '>', $self->{'basedir'} . '/subscriber_channel_positions/' . $self->{'clientId'} . '/' . $safe_channel ) ) {
            syswrite( STDERR, "$$: [_read_channel_feed] wrote position $$current_feed_id_ref:$new_feed_position\n" )
              if $self->{'DEBUG'};
            syswrite( $position_fh, $$current_feed_id_ref . ':' . $new_feed_position );
            close($position_fh);
        }
        @{ $self->{'channels'}{$channel} }{ 'current_feed_id', 'current_feed_position' } = ( $$current_feed_id_ref, $new_feed_position );
    }
    if ( !$leaveopen ) {
        delete $self->{'channels'}{$channel}{'fh'};
        close($feed_fh);
    }

    if ( $new_feed_position >= $MAX_FEED_SIZE ) {
        if ( my $found_next_feed = $self->_find_next_feed( $safe_channel, $$current_feed_id_ref ) ) {
            syswrite( STDERR, "$$: [_read_channel_feed] next feed_id : reached end of feed , going to next $$current_feed_id_ref moves to " . ( $$current_feed_id_ref + $found_next_feed ) . " in $channel\n" )
              if $self->{'DEBUG'};

            $$current_feed_id_ref += $found_next_feed;
            $$current_feed_position_ref = 0;
            my $changed_files = $self->_move_channel_to_next_feed( $channel, $$current_feed_id_ref );
            return ( $events_read, 1, $changed_files );
        }
    }

    $$current_feed_position_ref = $new_feed_position;
    syswrite( STDERR, "$$: [_read_channel_feed] read to the end of the feed for $safe_channel and no new ones are avaialble!\n" )
      if $self->{'DEBUG'};
    return ( $events_read, 0, 0 );
}

sub _get_channel_activate_feed_id {
    my $self         = shift;
    my $safe_channel = shift;
    my $writeable    = shift;
    Cpanel::SV::untaint($safe_channel);    # safe uri encoded

    syswrite( STDERR, "$$: [_get_channel_activate_feed_id] for $safe_channel\n" ) if $self->{'DEBUG'};

    my $feed_id;
    my $channel_feed_dir = $self->{'basedir'} . '/channels/' . $safe_channel . '/feed';
    if ( $self->{'current_channel_feed_dir'} eq $channel_feed_dir || opendir( $self->{'current_channel_feed_dir_fh'}, $channel_feed_dir ) ) {
        $self->{'current_channel_feed_dir'} = $channel_feed_dir;
        seekdir( $self->{'current_channel_feed_dir_fh'}, 0 );
        $feed_id = ( sort { $b <=> $a } grep ( !/^\./, readdir( $self->{'current_channel_feed_dir_fh'} ) ) )[0];
    }
    if ( !$feed_id ) {
        if ( open( my $fh, '>>', $self->{'basedir'} . '/channels/' . $safe_channel . '/feed/1' ) ) {
            close($fh);
        }
        else {
            warn "Failed to create channel feed for $safe_channel: $!";
        }
        syswrite( STDERR, "$$: [_get_channel_activate_feed_id] for $safe_channel -- no feeds, creating feed '1'\n" ) if $self->{'DEBUG'};

        return ( 1, $self->{'basedir'} . '/channels/' . $safe_channel . '/feed/1', 0 );
    }

    my $previous_feed;
    my $previous_feed_needs_ping = 0;

    if ($writeable) {

        # we may need to move to the next file if we are too big
        my $current_feed = $self->{'basedir'} . '/channels/' . $safe_channel . '/feed/' . $feed_id;
        my $feed_size;

        if ( $self->{'current_writeable_feed'} eq $current_feed || open( $self->{'current_writeable_feed_fh'}, '>>', $current_feed ) ) {
            $self->{'current_writeable_feed'} = $current_feed;
            $feed_size = ( stat( $self->{'current_writeable_feed_fh'} ) )[7];
        }

        if ( !defined $feed_size
            || $feed_size > $MAX_FEED_SIZE ) {
            if ( $feed_id - 1 > 0 ) {
                my $dead_feed_id = $feed_id - 1;
                ($dead_feed_id) = $dead_feed_id =~ /(\d+)/;    # untaint  -- safe always a number
                                                               #If we have reached the max size for the feed delete the previous one as we are moving on.
                $self->_remove_feed( $safe_channel, $dead_feed_id );
            }
            syswrite( STDERR, "$$: [_get_channel_activate_feed_id] previous channel feed is going to need a ping if we are about to add message\n" )
              if $self->{'DEBUG'};
            ($feed_id) = $feed_id =~ /(\d+)/;                  # untaint  -- safe always a number
            $previous_feed_needs_ping = 1;
            $previous_feed            = $self->{'basedir'} . '/channels/' . $safe_channel . '/feed/' . $feed_id;
            ++$feed_id;
        }
        elsif ( $self->{'DEBUG'} ) {
            syswrite( STDERR, "$$: [_get_channel_activate_feed_id] $safe_channel feed is is smaller then MAX\n" );
        }
    }

    ($feed_id) = $feed_id =~ /(\d+)/;
    return ( $feed_id, $self->{'basedir'} . '/channels/' . $safe_channel . '/feed/' . $feed_id, $previous_feed_needs_ping, $previous_feed );
}

sub _comet_ensure_dir {
    my $self = shift;
    my $dir  = shift;
    if ( !-e $self->{'basedir'} . '/' . $dir ) {
        if ( !-e $self->{'basedir'} ) {
            mkdir( $self->{'homedir'} . '/.cpanel',       0700 );
            mkdir( $self->{'homedir'} . '/.cpanel/comet', 0700 );
            mkdir( $self->{'basedir'},                    0700 );
        }
        if ( !-e $self->{'basedir'} ) {
            warn "Failed to create " . $self->{'basedir'} . ": $!";
            return 0;
        }
        my @dirs = split( m!/!, $dir );
        my @path;
        my $dirpart;
        foreach my $dir (@dirs) {
            push @path, $dir;
            $dirpart = join( '/', @path );
            Cpanel::SV::untaint($dirpart);    #untaint -- safe read from disk already exists
            syswrite( STDERR, "$$: [_comet_ensure_dir] mkdir [" . $self->{'basedir'} . '/' . $dirpart . "]\n" ) if $self->{'DEBUG'};
            mkdir( $self->{'basedir'} . '/' . $dirpart, 0700 );
        }
    }
    if ( !-e $self->{'basedir'} . '/' . $dir ) {
        warn "Failed to create " . $self->{'basedir'} . '/' . $dir . ": $!";
        return 0;
    }
}

sub _create_clientid {
    my $self = shift;
    $self->{'clientId'} = shift;
    if ( !$self->{'clientId'} ) {
        $self->{'clientId'} = Cpanel::Rand::Get::getranddata( 16, [ 0 .. 9, 'A' .. 'Z', 'a' .. 'z' ] );
        my $client_safe = 0;
        while ( -e $self->{'basedir'} . '/subscriptions/' . $self->{'clientId'} && ++$client_safe < 1024 ) {
            $self->{'clientId'} = Cpanel::Rand::Get::getranddata( 16, [ 0 .. 9, 'A' .. 'Z', 'a' .. 'z' ] );
        }
    }
    ( $self->{'clientId'} ) = $self->{'clientId'} =~ m!([A-Za-z0-9]+)!;    # untaint -- safe from trusted source or generated
    return 1 if -e $self->{'basedir'} . '/subscriptions/' . $self->{'clientId'};
    $self->_comet_ensure_dir('subscriptions');
    return 0                                                                                                                if !$self->{'clientId'};
    syswrite( STDERR, "[_create_clientid] mkdir [" . $self->{'basedir'} . '/subscriptions/' . $self->{'clientId'} . "]\n" ) if $self->{'DEBUG'};
    return mkdir( $self->{'basedir'} . '/subscriptions/' . $self->{'clientId'}, 0700 ) ? 1 : 0;
}

sub _find_next_feed {
    my $self = shift;
    my ( $safe_channel, $current_feed_id ) = @_;
    my $found_next_feed;
    for ( 1 .. $MAX_FEED_SEARCH_ATTEMPTS ) {
        if ( -e $self->{'basedir'} . '/channels/' . $safe_channel . '/feed/' . ( $current_feed_id + $_ ) ) {
            $found_next_feed = $_;
            last;
        }
    }
    syswrite( STDERR, "$$: [_find_next_feed] result = " . ( $found_next_feed || "NULL" ) . "\n" )
      if $self->{'DEBUG'};

    return $found_next_feed;
}

sub _get_user {
    my $self = shift;
    my $user = '';

    if ( $ENV{'REMOTE_USER'} ) {
        $user = $ENV{'REMOTE_USER'};
    }
    else {
        $user = ( Cpanel::PwCache::getpwuid($>) )[0];
    }

    return Cpanel::Encoder::URI::uri_encode_str($user);
}

DESTROY {
    unlink($INOTIFY_ALARM_TRICK_FILE) if $INOTIFY_ALARM_TRICK_FILE;
}
1;
