package Whostmgr::Exim;

# cpanel - Whostmgr/Exim.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::Rand                ();
use Cpanel::SafeRun::Simple     ();
use Cpanel::JSON                ();
use Cpanel::Logger              ();
use Cpanel::CloseFDs            ();
use Cpanel::ForkAsync           ();
use Cpanel::Exim                ();
use Cpanel::Exim::Utils         ();
use Cpanel::Exim::Options       ();
use Cpanel::SafeRun::Errors     ();
use Cpanel::SafeRun::Dynamic    ();
use Cpanel::Sys::Setsid::Fast   ();
use Cpanel::Exim::Config::Check ();

my %SIZE_MULTIPLIER = ( 'K' => 1024, 'M' => 1024 * 1024 );
my $SIZE_PREFIXES   = join( q{}, keys %SIZE_MULTIPLIER );

sub fetch_mail_queue {
    my ( $opt_ref, $searchfunc ) = @_;

    my @messages;
    my $exim_bin = Cpanel::Exim::find_exim();

    my $before_filter_count = 0;

    if ( -x $exim_bin && open my $exim_fh, ( join( ' ', $exim_bin, Cpanel::Exim::Options::fetch_exim_options(), '-bpra' ) . '|' ) ) {    #safesecure2
        my ( $extra, $buffer );
        while ( my $line = readline $exim_fh ) {
            $line =~ s/^\s+//;
            chomp $line;
            my %message;
            ( undef, @message{ 'size', 'msgid', 'sender' }, $extra ) = ( split /\s+/, $line, 5 );

            #int( .5 + ... ) is for rounding.
            if ( $message{'size'} =~ m{\A(.*)([$SIZE_PREFIXES])\z} ) {
                $message{'size'} = int( .5 + $1 * $SIZE_MULTIPLIER{$2} );
            }

            $message{'time'} = Cpanel::Exim::Utils::get_time_from_msg_id( $message{'msgid'} );

            $message{'frozen'} = ( $extra =~ /\*\*\s+frozen/ ? 1 : 0 );
            $message{'user'}   = ( $extra =~ /\(([^\)]+)\)/ ) ? $1 : undef;
            $message{'sender'} =~ s/^\<//;
            $message{'sender'} =~ s/\>$//;

            my %recps;
            while ( $buffer = readline $exim_fh ) {
                chomp $buffer;
                $buffer =~ s/^\s+//;
                if ( $buffer =~ s/^\+D\s+// ) {
                    $recps{$buffer} = 2;
                }
                elsif ( $buffer =~ s/^\D\s+// ) {
                    $recps{$buffer} = 1;
                }
                elsif ( !$buffer ) {
                    last;
                }
                else {
                    $recps{$buffer} = 0;
                }
            }
            $message{'recipients'} = [ keys %recps ];

            ++$before_filter_count;

            if ( !$searchfunc || $searchfunc->( \%message ) ) {
                push @messages, \%message;
            }
        }

        close $exim_fh;
    }
    else {
        my $logger = Cpanel::Logger->new();
        $logger->warn('Failed to launch exim to interrogate message queue');
        return ( 0, 'Failed to launch exim to interrogate message queue', [] );
    }

    return ( 1, 'Fetched Sorted Rows', \@messages, $before_filter_count );
}

sub unfreeze_messages_mail_queue {
    my $opt_ref = shift || {};

    my @msgids = _fetch_msgids_from_opt_ref($opt_ref);

    my $exim_bin = Cpanel::Exim::find_exim();
    if ( !$exim_bin )    { return ( 0, "Failed to locate exim binary" ); }
    if ( !-x $exim_bin ) { return ( 0, "Failed to locate executable exim binary" ); }

    _process_msgids( \@msgids, '-Mt', $opt_ref->{'channel'} );
    return ( 1, "Mail queue remove started in background", "Removal Run Started" );
}

sub remove_messages_mail_queue {
    my $opt_ref = shift || {};

    my @msgids = _fetch_msgids_from_opt_ref($opt_ref);

    my $exim_bin = Cpanel::Exim::find_exim();
    if ( !$exim_bin )    { return ( 0, "Failed to locate exim binary" ); }
    if ( !-x $exim_bin ) { return ( 0, "Failed to locate executable exim binary" ); }

    _process_msgids( \@msgids, '-Mrm', $opt_ref->{'channel'}, $opt_ref->{'do_after'} );
    return ( 1, "Mail queue remove started in background", "Removal Run Started" );
}

sub deliver_messages_mail_queue {
    my $opt_ref = shift || {};

    my @msgids = _fetch_msgids_from_opt_ref($opt_ref);

    my $exim_bin = Cpanel::Exim::find_exim();
    if ( !$exim_bin )    { return ( 0, "Failed to locate exim binary" ); }
    if ( !-x $exim_bin ) { return ( 0, "Failed to locate executable exim binary" ); }

    _process_msgids( \@msgids, '-M', $opt_ref->{'channel'} );

    return ( 1, "Mail queue delivery started in background", "Queue Run Started" );

    #my $msg = Cpanel::SafeRun::Errors::saferunallerrors( $exim_bin, Cpanel::Exim::Options::fetch_exim_options(), '-v', '-M', $msgid );
    #my @output = split( /\n/, $msg );
    #my %POSSIBLE_STATUS = (
    #    '**' => 2,    #'failed',
    #    '==' => 3,    #'defer',
    #    '=>' => 4,    #'delivered'
    #    '->' => 4,    #'delivered'
    #);
    #my $statusmsg;
    #my $status = 1;
    #foreach my $line ( reverse @output ) {
    #    if ( $line =~ /^\s+(\*\*|==|=\>)\s*(.*)/ ) {
    #        $status    = $POSSIBLE_STATUS{$1};
    #        $statusmsg = $2;
    #    }
    #}
}

sub _process_msgids {

    my ( $ids_ref, $cmd, $channel, $callback ) = @_;

    Cpanel::ForkAsync::do_in_child(
        sub {
            Cpanel::Sys::Setsid::Fast::fast_setsid();
            Cpanel::CloseFDs::redirect_standard_io_dev_null();
            open( STDERR, '>>', '/usr/local/cpanel/logs/error_log' );
            require Cpanel::Comet;
            my $exim_bin = Cpanel::Exim::find_exim();
            my $comet    = $channel ? Cpanel::Comet->new( 'DEBUG' => 0 ) : 0;
            foreach my $msgid ( @{$ids_ref} ) {
                _push_cmd_to_comet_channel( $comet, $channel, [ $exim_bin, Cpanel::Exim::Options::fetch_exim_options(), '-v', $cmd, $msgid ] );

            }

            if ($callback) {
                $callback->();
            }

            _signal_end_of_comet_channel( $comet, $channel );
            exit;
        }
    );

    return;
}

sub deliver_mail_queue {
    my $opt_ref  = shift || {};
    my $channel  = $opt_ref->{'channel'};
    my $exim_bin = Cpanel::Exim::find_exim();
    if ( !$exim_bin )    { return ( 0, "Failed to locate exim binary" ); }
    if ( !-x $exim_bin ) { return ( 0, "Failed to locate executable exim binary" ); }
    my @command = ( $exim_bin, '-qff', '-v', Cpanel::Exim::Options::fetch_exim_options() );

    Cpanel::ForkAsync::do_in_child(
        sub {
            Cpanel::Sys::Setsid::Fast::fast_setsid();
            Cpanel::CloseFDs::redirect_standard_io_dev_null();
            open( STDERR, '>>', '/usr/local/cpanel/logs/error_log' );
            require Cpanel::Comet;
            my $comet = $channel ? Cpanel::Comet->new( 'DEBUG' => 0 ) : 0;
            _push_cmd_to_comet_channel( $comet, $channel, \@command, 1 );
            _signal_end_of_comet_channel( $comet, $channel );

            exit;
        }
    );

    return ( 1, "Mail queue delivery started in background", "Queue Run Started" );
}

sub purge_mail_queue {
    my $opt_ref = shift || {};

    my $exim_bin = Cpanel::Exim::find_exim();
    if ( !$exim_bin )    { return ( 0, "Failed to locate exim binary" ); }
    if ( !-x $exim_bin ) { return ( 0, "Failed to locate executable exim binary" ); }

    my @msgids = map { /(\w+\-\w+\-\w+)/ ? $1 : () } split( /\n/, Cpanel::SafeRun::Simple::saferun( $exim_bin, Cpanel::Exim::Options::fetch_exim_options(), '-bpr' ) );

    _process_msgids( \@msgids, '-Mrm', $opt_ref->{'channel'} );

    return ( 1, "Mail queue remove started in background", "Removal Run Started" );
}

sub _fetch_msgids_from_opt_ref {
    my $opt_ref = shift;
    my @msgids;
    if ( exists $opt_ref->{'msgids'} ) {
        if ( ref $opt_ref->{'msgids'} eq 'ARRAY' ) {
            push @msgids, @{ $opt_ref->{'msgids'} };
        }
        else {
            push @msgids, split( /\,/, $opt_ref->{'msgids'} );
        }
    }
    elsif ( $opt_ref->{'msgid'} ) {
        push @msgids, $opt_ref->{'msgid'};
    }
    return wantarray ? @msgids : \@msgids;
}

sub _push_cmd_to_comet_channel {
    my $comet   = shift;
    my $channel = shift;
    my $cmd_ref = shift;
    my $delay   = shift;

    my $last_time = 0;
    my $buffer    = '';

    Cpanel::SafeRun::Dynamic::saferun_callback(
        'prog'     => $cmd_ref,
        'callback' => sub {

            # rate limited to one msg per second
            my $time = time();
            if ( !$delay || $time != $last_time ) {
                $last_time = time();
                $comet->add_message(
                    $channel,
                    Cpanel::JSON::Dump(
                        {
                            'data'    => $buffer . shift,
                            'channel' => $channel,
                        }
                    )
                ) if $comet;
                $buffer = '';
            }
            else {
                $buffer .= shift;
            }
        }
    );
    $comet->add_message(
        $channel,
        Cpanel::JSON::Dump(
            {
                'data'    => $buffer,
                'channel' => $channel,
            }
        )
      )
      if $buffer
      && $comet;
}

sub _signal_end_of_comet_channel {
    my $comet   = shift;
    my $channel = shift;
    $comet->add_message(
        $channel,
        Cpanel::JSON::Dump(
            {
                'data'     => 'End of channel',
                'channel'  => $channel,
                'complete' => 1,
            }
        )
    ) if $comet;
    $comet->purgeclient() if $comet;
}

sub validate_exim_configuration_syntax {
    my $ref      = shift;
    my $section  = $ref->{'section'};
    my $cfg_text = $ref->{'cfg_text'};

    my ( $test_cfg_file, $test_cfg_fh ) = Cpanel::Rand::get_tmp_file_by_name('/etc/exim.conf.test');
    my $line_offset = 0;
    if ($section) {
        $line_offset++;
        print {$test_cfg_fh} "begin $section\n";
    }
    print {$test_cfg_fh} $cfg_text;
    close($test_cfg_fh);

    my $ret      = {};
    my $goodconf = Cpanel::Exim::Config::Check::check_exim_config( $ret, $test_cfg_file, $line_offset );

    $ret->{'status'} = $goodconf;
    unlink($test_cfg_file);
    return $ret;
}

sub get_cpanel_defined_exim_settings_map {
    my $cpanel_defined_exim_settings = ( split( /begin acl/, Cpanel::SafeRun::Errors::saferunnoerror( '/usr/local/cpanel/scripts/eximconfgen', '--local=/dev/null', '--localopts=/dev/null', '--localopts.shadow=/dev/null' ) ) )[0];
    my $parsed_config                = parse_exim_config($cpanel_defined_exim_settings);
    return { map { $_->{'setting'} => $_->{'val'} } @{$parsed_config} };
}

sub parse_exim_config {
    my $generated_exim_settings = shift;

    my @settings;
    $generated_exim_settings = join( " ", split( /\\\s*[\n\r]+/, $generated_exim_settings ) );
    foreach my $line ( split( /\n/, $generated_exim_settings ) ) {
        $line =~ s/^\s*//;
        $line =~ s/\s*$//;
        next if ( $line =~ /^#/ );
        if (
            $line =~ /
                          ^
                          (?:hide\s+)?                                             # Hide modifier is optional for all directives.
                          (?:(hostlist|domainlist|addresslist|localpartlist)\s+)?  # These are named lists. We store the list type as the "name" of the directive
                          ([^\s=]+)\s*                                             # The list name or the setting if it's not a named list
                          =                                                        # only match lines that are setting a value
                      /x
        ) {
            my $setting_name = $1 // $2;    # This will grab the listtype if the line is a list definition, or the setting name otherwise
            my ( $combined_setting, $value ) = split( /\s*=\s*/, $line, 2 );
            push @settings,
              {
                'name'    => ( $setting_name =~ /^\s*[A-Z]/ ? 'MACRO' : $setting_name ),
                'setting' => $combined_setting,
                'val'     => $value
              };

        }

    }

    my @lists =
      sort { $a->{'setting'} cmp $b->{'setting'} } grep { $_->{'name'} eq 'domainlist' || $_->{'name'} eq 'hostlist' || $_->{'name'} eq 'addresslist' || $_->{'name'} eq 'localpartlist' } @settings;
    my @macros = sort { $a->{'setting'} cmp $b->{'setting'} } grep { $_->{'name'} =~ /^\s*[A-Z]/ } @settings;
    return [
        @macros, @lists,
        sort { $a->{'setting'} cmp $b->{'setting'} } grep {
                 $_->{'name'} !~ /^\s*[A-Z]/
              && $_->{'name'} ne 'domainlist'
              && $_->{'name'} ne 'hostlist'
              && $_->{'name'} ne 'addresslist'
              && $_->{'name'} ne 'localpartlist'

        } @settings

    ];
}

sub validate_routelist {
    my $routelist = shift;

    return validate_exim_configuration_syntax(
        {
            'cfg_text' => qq{
begin routers

dummy:
driver = manualroute
route_list = $routelist
transport = dummy

begin transports

dummy:
driver = smtp
}
        }
    );

}
1;
