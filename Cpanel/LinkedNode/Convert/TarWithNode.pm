package Cpanel::LinkedNode::Convert::TarWithNode;

# cpanel - Cpanel/LinkedNode/Convert/TarWithNode.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Convert::TarWithNode

=head1 SYNOPSIS

    Cpanel::LinkedNode::Convert::TarWithNode::send(
        tar => \%tar_args,
        websocket => \%websocket_args,
    );

    # … or to receive:
    Cpanel::LinkedNode::Convert::TarWithNode::receive(
        tar => \%tar_args,
        websocket => \%websocket_args,
    );

=head1 DESCRIPTION

This module encapsulates logic to stream content via L<tar(1)> over
WebSocket to or from a linked node’s cpsrvd C<TarRestore> endpoint.

This module assumes use of L<AnyEvent>.

=cut

#----------------------------------------------------------------------

use Carp         ();
use AnyEvent     ();
use Promise::XS  ();
use IO::SigGuard ();

use Cpanel::Async::Waitpid                     ();
use Cpanel::ChildErrorStringifier              ();
use Cpanel::IOCallbackWriteLine::Buffer        ();
use Cpanel::LinkedNode::Worker::WHM::WebSocket ();
use Cpanel::LoadModule                         ();
use Cpanel::PromiseUtils                       ();
use Cpanel::Streamer::ReportUtil               ();

use constant REQ_ARGS => qw( tar websocket );

use constant {
    _DEBUG => 0,

    _TO_ATTR   => 'to',
    _FROM_ATTR => 'from',
};

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 send( %OPTS )

Sends the tar archive. %OPTS are:

=over

=item * C<tar> - A hashref of args as given to
L<Cpanel::Streamer::TarBackup>’s constructor.

=item * C<websocket> - A hashref of args as given to
L<Cpanel::LinkedNode::Worker::WHM::WebSocket>’s C<connect()> function.

=back

Nothing is returned.

=cut

sub send (@opts_kv) {
    return _transfer(
        'Cpanel::Streamer::TarBackup',
        'Cpanel::Interconnect::ToWebSocket',
        _FROM_ATTR,
        @opts_kv,
    );
}

=head2 receive( %OPTS )

Receives/restores the tar archive. %OPTS are as for C<send()>,
but C<tar> is the arguments given to L<Cpanel::Streamer::TarRestore>’s
constructor.

=cut

sub receive (@opts_kv) {
    return _transfer(
        'Cpanel::Streamer::TarRestore',
        'Cpanel::Interconnect::FromWebSocket',
        _TO_ATTR,
        @opts_kv,
    );
}

=head2 receive_p( %OPTS )

Like L<receive()> except it returns the underlying promise object
allowing callers to process it as they see fit.

=cut

sub receive_p {
    return _transfer_p(
        'Cpanel::Streamer::TarRestore',
        'Cpanel::Interconnect::FromWebSocket',
        _TO_ATTR,
        @_,
    );
}

sub _transfer ( $tar_class, $ic_class, $dir, %opts ) {    ## no critic qw(ManyArgs) - mis-parse

    my $p = _transfer_p( $tar_class, $ic_class, $dir, %opts );

    Cpanel::PromiseUtils::wait_anyevent($p);

    return;
}

sub _transfer_p ( $tar_class, $ic_class, $dir, %opts ) {    ## no critic qw(ProhibitManyArgs)

    my $err_sr = \do { my $v = undef };

    my @missing = grep { !length $opts{$_} } REQ_ARGS();
    Carp::confess "need: @missing" if @missing;

    my $transfer_is_send = ( $dir eq _FROM_ATTR );

    Cpanel::LoadModule::load_perl_module($_) for ( $tar_class, $ic_class );

    my $tar_streamer = $tar_class->new(
        %{ $opts{'tar'} },
    );

    _debug('tar streamer created');

    my $warn_cr = $opts{'on_warn'} || sub ($warning) { warn $warning };

    my $start_cr = $opts{'on_start'};

    my @subscriptions;

    # Before we send out for the WebSocket connection let’s ensure that
    # we actually started tar correctly.
    return Cpanel::Streamer::ReportUtil::get_child_error_id_p($tar_streamer)->then(
        sub ($xid) {
            if ($xid) {

                # Welp, tar failed to start. We have an exception ID (XID),
                # so let’s report that. But first we’ll wait for the
                # process we _wanted_ to exec tar to finish.

                my $pid = $tar_streamer->get_attr('pid');

                require Cpanel::Async::Waitpid;
                return Cpanel::Async::Waitpid::timed($pid)->finally(
                    sub { Promise::XS::rejected("XID: $xid") },
                );
            }
        }
    )->then(
        sub {
            Cpanel::LinkedNode::Worker::WHM::WebSocket::connect(
                %{ $opts{'websocket'} },
            );
        }
    )->then(
        sub ($courier) {
            _debug('websocket session created');

            push @subscriptions, $courier->create_subscription(
                error => sub ($why) {
                    _debug( "WebSocket error - " . __PACKAGE__ );

                    _kill_tar($tar_streamer);

                    # We don’t call $cv_croak_cr here because the
                    # $ic’s promise will still reject.
                },
            );

            my $ic = $ic_class->new(
                $tar_streamer->get_attr($dir),
                $courier,
            );

            my $liner = Cpanel::IOCallbackWriteLine::Buffer->new(
                sub ($line) {
                    $line .= "\n" if $line !~ m<\n\z>;
                    $warn_cr->("Unexpected tar output: $line");
                }
            );

            my $recv_rdr;
            $recv_rdr = !$transfer_is_send && do {
                my $fh = $tar_streamer->get_attr(_FROM_ATTR);

                AnyEvent->io(
                    fh   => $fh,
                    poll => 'r',
                    cb   => sub {
                        my $got = IO::SigGuard::sysread( $fh, my $buf, 65535 );

                        if ($got) {
                            $liner->feed($buf);
                        }
                        else {
                            if ( !defined $got ) {
                                $warn_cr->("failed to read from tar: $!");
                                close $fh;
                            }

                            undef $recv_rdr;
                        }
                    },
                );
            };

            push @subscriptions, $ic->create_subscription(
                message => sub ($payload) {
                    $warn_cr->("Unexpected output from tar: $payload");
                },
            );

            $start_cr->() if $start_cr;

            my $promise = $ic->run()->then(
                _make_completion_handler( $courier, $tar_streamer ),
            )->catch(
                _make_failure_handler( $courier, $tar_streamer, $err_sr ),
            )->finally(
                sub { $liner->clear() },
            );

            # If we’re sending, then we have to close the WS connection.
            # If we’re receiving, then the connection is already closed.
            if ($transfer_is_send) {
                $promise = $promise->then(
                    _make_finish_handler($courier),
                );
            }

            return $promise->finally( sub { undef $recv_rdr } );
        },
    )->then(
        sub {
            if ($$err_sr) { return Promise::XS::rejected($$err_sr) }
        }
    )->finally( sub { @subscriptions = () } );
}

sub _make_completion_handler ( $courier, $tar_streamer ) {
    return sub {

        _debug('finished streaming');

        my $pid = $tar_streamer->get_attr('pid');

        _debug("reaping tar process ($pid)");

        return Cpanel::Async::Waitpid::timed(
            $tar_streamer->get_attr('pid'),
        )->then(
            sub ($cerr) {
                _debug("done waitpid: $cerr");
                my $cerrstr = Cpanel::ChildErrorStringifier->new( $cerr, 'tar' );
                my $autopsy = $cerrstr->autopsy();

                my $ret;

                if ( $cerrstr->signal_code() ) {
                    _debug("tar failed: $autopsy");

                    $ret = Promise::XS::rejected( $cerrstr->to_exception() );
                }
                elsif ($cerr) {
                    if ( my $xid = Cpanel::Streamer::ReportUtil::get_child_error_id($tar_streamer) ) {
                        $ret = Promise::XS::rejected("XID $xid");
                    }
                    else {
                        warn "tar failed: $autopsy\n";
                    }
                }

                _debug('closing websocket');

                return $ret || ['SUCCESS'];
            }
        );

    };
}

sub _make_failure_handler ( $courier, $tar_streamer, $err_sr ) {
    return sub ($why) {
        _debug("failure");
        $$err_sr = $why;

        my @finish_args = ('INTERNAL_ERROR');

        if ( eval { $why->isa('Cpanel::Exception') } ) {
            if ( $why->isa('Cpanel::Exception::Timeout') ) {
                _kill_tar($tar_streamer);
            }

            push @finish_args, "XID " . $why->id();
        }

        return \@finish_args;
    };
}

sub _make_finish_handler ($courier) {
    return sub ($finish_args_ar) {
        _debug("closing websocket: @$finish_args_ar");

        return $courier->finish(@$finish_args_ar)->catch( sub ($why) { warn $why; } )->finally(
            sub {
                _debug('websocket closed');
            }
        );
    };
}

sub _kill_tar ($tar_streamer) {
    require Cpanel::Kill::Single;
    Cpanel::Kill::Single::safekill_single_pid( $tar_streamer->get_attr('pid') );

    return;
}

sub _debug ($str) {
    print STDERR "$str\n" if _DEBUG;

    return;
}

1;

