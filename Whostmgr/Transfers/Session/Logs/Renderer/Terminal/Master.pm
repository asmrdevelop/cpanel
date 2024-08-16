package Whostmgr::Transfers::Session::Logs::Renderer::Terminal::Master;

# cpanel - Whostmgr/Transfers/Session/Logs/Renderer/Terminal/Master.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::JSON                        ();
use Cpanel::Locale                      ();
use Cpanel::LocaleString                ();
use Cpanel::StringFunc::Fmt             ();
use Cpanel::Output::Formatted::Terminal ();
use Cpanel::Output::Terminal            ();
use Cpanel::Time::Local                 ();

#Arguments:
#
#   on_render_message - (optional) a callback that the object calls after each
#                       successful render_message() call. It receives the
#                       data structure that represents the message.
#
sub new {
    my ( $class, %OPTS ) = @_;

    my @msg_render_map = (
        {
            type   => 'warnings',
            color  => Cpanel::Output::Terminal::COLOR_WARN(),
            phrase => Cpanel::LocaleString->new('[quant,_1,warning,warnings]'),
        },
        {
            type   => 'dangerous_items',
            color  => Cpanel::Output::Terminal::COLOR_ERROR(),
            phrase => Cpanel::LocaleString->new('[quant,_1,dangerous item,dangerous items]'),
        },
        {
            type   => 'skipped_items',
            color  => Cpanel::Output::Terminal::COLOR_WARN(),
            phrase => Cpanel::LocaleString->new('[quant,_1,skipped item,skipped items]'),
        },
        {
            type   => 'altered_items',
            color  => Cpanel::Output::Terminal::COLOR_WARN(),
            phrase => Cpanel::LocaleString->new('[quant,_1,altered item,altered items]'),
        },
    );

    my $self = {
        '_locale'            => Cpanel::Locale->get_handle(),
        '_on_render_message' => $OPTS{'on_render_message'},
        '_output_obj'        => Cpanel::Output::Formatted::Terminal->new(),
        '_msg_render_map'    => \@msg_render_map,
    };

    bless $self, $class;

    return $self;
}

#Sets the "on_render_message" parameter that could also have been passed in
#via the constructor.
#
sub set_on_render_message {
    my ( $self, $coderef ) = @_;

    $self->{'_on_render_message'} = $coderef;

    return 1;
}

sub keepalive {
    my ($self) = @_;

    return;
}

sub render_message {    ## no critic qw(ProhibitExcessComplexity)
    my ( $self, $message ) = @_;

    my $message_ref = eval { Cpanel::JSON::Load($message) };

    if ($@) {
        chomp($message);
        $self->_print_formatted_message( { 'pid' => 'ERROR' }, Cpanel::Output::Terminal::COLOR_ERROR(), $self->{'_locale'}->maketext( "Error: [_1]", $message ) );
        return;
    }

    if ( $message_ref->{'type'} eq 'control' ) {
        my $pid      = $message_ref->{'pid'};
        my $contents = $message_ref->{'contents'};
        my $action   = $contents->{'action'};
        if ( $action eq 'start-item' ) {

            #noop
        }
        elsif ( $action eq 'process-item' ) {

            #noop
        }
        elsif ( $action eq 'initiator' ) {

            #noop
        }
        elsif ( $action eq 'child-failed' ) {

            my ( $count, $limit ) = split( '/', $message_ref->{'contents'}{'msg'}, 2 );    # number/number
            $self->_print_formatted_message(
                $message_ref,
                'bold blue on_red',
                $self->{'_locale'}->maketext( "Child process “[_1]” died (retry [numf,_2] of [numf,_3]).", $pid, $count, $limit )
            );

        }
        elsif ( $action eq 'start' ) {
            if ( $contents->{'item_name'} ) {
                my $localized_item_name = $contents->{'item_name'};
                $self->_print_formatted_message(
                    $message_ref,
                    '',

                    ( $contents->{'local_item'} && $contents->{'local_item'} ne $contents->{'item'} )
                    ?

                      $self->{'_locale'}->maketext( "Starting “[_1]”: “[_2]” → “[_3]”[comment,## no extract maketext (will be done via task 32670)]", $localized_item_name, $contents->{'item'}, $contents->{'local_item'} )
                    : $self->{'_locale'}->maketext( "Starting “[_1]”: [_2]", $localized_item_name, $contents->{'item'} )
                );
            }
            else {
                $self->_print_formatted_message(
                    $message_ref,
                    'blue',
                    $self->{'_locale'}->maketext("Start Session")
                );
            }
        }
        elsif ( $action eq 'version' ) {
            $self->_print_formatted_message(
                $message_ref,
                '',
                $self->{'_locale'}->maketext( "Version: [_1]", $message_ref->{'contents'}{'msg'} )
            );
        }
        elsif ( $action eq 'pausing' ) {
            $self->_print_formatted_message(
                $message_ref,
                'blue',
                $self->{'_locale'}->maketext("Pausing")
            );
        }
        elsif ( $action eq 'aborting' ) {
            $self->_print_formatted_message(
                $message_ref,
                'blue',
                $self->{'_locale'}->maketext("Aborting …")
            );
        }
        elsif ( $action eq 'pause' ) {
            $self->_print_formatted_message(
                $message_ref,
                'blue',
                $self->{'_locale'}->maketext("Paused")
            );

        }
        elsif ( $action eq 'resume' ) {
            $self->_print_formatted_message(
                $message_ref,
                'blue',
                $self->{'_locale'}->maketext("Resumed")
            );

        }
        elsif ( $action eq 'abort' ) {
            $self->_print_formatted_message(
                $message_ref,
                'bold blue',
                $self->{'_locale'}->maketext("Session Aborted")
            );
        }
        elsif ( $action eq 'fail' ) {
            $self->_print_formatted_message(
                $message_ref,
                'bold blue',
                $self->{'_locale'}->maketext("Session Failed")
            );
        }
        elsif ( $action eq 'complete' ) {
            if ( $contents->{'child_number'} ) {
                $self->_print_formatted_message(
                    $message_ref,
                    'blue',
                    $self->{'_locale'}->maketext("Child Complete")
                );
            }
            else {
                $self->_print_formatted_message(
                    $message_ref,
                    'bold blue',
                    $self->{'_locale'}->maketext("Session Complete")
                );
            }
        }
        elsif ( $action eq "remotehost" ) {
            $self->_print_formatted_message(
                $message_ref,
                'bold magenta',
                $self->{'_locale'}->maketext( "Remote Host: [_1]", $message_ref->{'contents'}{'msg'} )
            );

        }
        elsif ( $action eq "queue_count" ) {
            $self->_print_formatted_message(
                $message_ref,
                'bold blue',
                $self->{'_locale'}->maketext( "Queue “[_1]” items: [_2]", $message_ref->{'contents'}{'queue'}, $message_ref->{'contents'}{'msg'} )
            );

        }
        elsif ( $action eq "queue_size" ) {
            $self->{'_queue_size'}{ $message_ref->{'contents'}{'queue'} } = {
                'total'     => $message_ref->{'contents'}{'msg'},
                'completed' => 0
            };
        }
        elsif ( $action eq 'success-item' || $action eq 'warning-item' || $action eq 'failed-item' ) {
            my $messages = $message_ref->{'contents'}{'msg'};
            my @items;
            my $summary;

            my $color = $action eq 'success-item' ? Cpanel::Output::Terminal::COLOR_SUCCESS() : $action eq 'warning-item' ? Cpanel::Output::Terminal::COLOR_WARN() : Cpanel::Output::Terminal::COLOR_ERROR();

            if ( $messages && ref $messages ) {
                foreach my $render_map ( @{ $self->{'_msg_render_map'} } ) {
                    if ( $messages->{ $render_map->{'type'} } ) {
                        push(
                            @items,
                            $self->{'_output_obj'}->format_message(
                                $render_map->{'color'},
                                $render_map->{'phrase'}->clone_with_args( $messages->{ $render_map->{'type'} } )->to_string(),
                            ),
                        );
                    }
                }
                $summary = $messages->{'failure'} || $messages->{'message'};
            }
            $summary ||= ( $action eq 'success-item' ? $self->{'_locale'}->maketext("Success") : $action eq 'warning-item' ? $self->{'_locale'}->maketext("Warning") : $self->{'_locale'}->maketext("Failed") );

            my $part1 = $self->{'_output_obj'}->format_message(
                $color,
                ( $contents->{'local_item'} && $contents->{'local_item'} ne $contents->{'item'} )

                  # Renamed item
                ? $self->{'_locale'}->maketext( "[_1] “[_2]” → “[_3]”: [_4][comment,## no extract maketext (will be done via task 32670)]", $contents->{'item_name'}, $contents->{'item'}, $contents->{'local_item'}, $summary )

                  # Same name item
                : $self->{'_locale'}->maketext( "[_1] “[_2]”: [_3][comment,## no extract maketext (will be done via task 32670)]", $contents->{'item_name'}, $contents->{'item'}, $summary )
            );

            $self->_print_formatted_message(
                $message_ref,
                '',
                ( @items ? $self->{'_locale'}->maketext( "[_1] ([list_and,_2])[comment,## no extract maketext (will be done via task 32670)]", $part1, \@items ) : $part1 )
            );
            if ( $messages->{'size'} ) {
                $self->_show_percentage($message_ref);
            }
        }
        else {
            print $self->{'_locale'}->maketext( "Unknown action: [_1]", $action ) . "\n";
        }
    }

    if ( $self->{'_on_render_message'} ) {
        $self->{'_on_render_message'}->($message_ref);
    }

    return;
}

sub _show_percentage {
    my ( $self, $message_ref ) = @_;

    my $queue    = $message_ref->{'contents'}{'queue'};
    my $messages = $message_ref->{'contents'}{'msg'};
    my $time     = $message_ref->{'contents'}{'time'} || $message_ref->{'contents'}{'msg'}{'time'};
    my $size     = $messages->{'size'};

    $self->{'_queue_size'}{$queue}{'completed'} += int($size);
    my $pctComplete = int( ( $self->{'_queue_size'}{$queue}{'completed'} / $self->{'_queue_size'}{$queue}{'total'} ) * 100 );

    $self->_print_formatted_message(
        $message_ref,
        'bold black on_blue',
        $time
        ? $self->{'_locale'}->maketext( "Progress: [numf,_1]% ([_2])", $pctComplete, Cpanel::Time::Local::localtime2timestamp($time) )
        : $self->{'_locale'}->maketext( "Progress: [numf,_1]%", $pctComplete )
    );

    return;
}

sub _print_formatted_message {
    my ( $self, $message_ref, $color, $message ) = @_;

    my $queue        = $message_ref->{'contents'}{'queue'};
    my $child_number = $message_ref->{'contents'}{'child_number'};
    my $pid          = $message_ref->{'pid'};

    # Changed for legibility
    my $pid_info = Cpanel::StringFunc::Fmt::fixed_length( $pid, 6, $Cpanel::StringFunc::Fmt::ALIGN_RIGHT );
    my $job_info = Cpanel::StringFunc::Fmt::fixed_length( ( $child_number ? "$queue:$child_number" : "MASTER" ), 10 );
    my $txt      = $color ? $self->{'_output_obj'}->format_message( $color, $message ) : $message;

    return print $self->{'_output_obj'}->format_message( 'base1', "[" . $pid_info . "][" . $job_info . "]: " ) . $txt . "\n";
}

1;
