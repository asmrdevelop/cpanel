package Cpanel::Parallelizer;

# cpanel - Cpanel/Parallelizer.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Try::Tiny;

use IO::Select                   ();
use Cpanel::FHUtils::Blocking    ();
use Cpanel::AdminBin::Serializer ();

sub new {
    my ( $class, %self ) = @_;
    $self{'process_limit'}      ||= 25;      # Number of simultaneous processes
    $self{'total_time_limit'}   ||= 3600;    # Maximum total running time: One hour by default
    $self{'process_time_limit'} ||= 1800;    # Maximum running time for a single child process: 30 minutes by default
    $self{'running'}     = 0;
    $self{'_processes_'} = {
        'running' => [],
        'queued'  => [],
    };
    $self{'start_time'} = 0;
    return bless \%self, $class;
}

sub _set_get {
    my $self = shift;
    my $key  = shift;
    my $val  = shift;
    if ( defined $val ) {
        $self->{$key} = $val;
    }
    return $self->{$key};
}

sub process_limit {
    my $self = shift;
    my $val  = shift;
    return $self->_set_get( 'process_limit', $val );
}

sub process_time_limit {
    my $self = shift;
    my $val  = shift;
    return $self->_set_get( 'process_time_limit', $val );
}

sub total_time_limit {
    my $self = shift;
    my $val  = shift;
    return $self->_set_get( 'total_time_limit', $val );
}

sub running {
    my $self = shift;

    # This one is only changed by calling the queue() or run() methods
    return $self->{'running'};
}

sub start_time {
    my $self = shift;

    # This one is only changed by calling the run() or join() methods
    return $self->{'start_time'};
}

sub run {
    my $self = shift;
    return 1 unless $self->running();

    my $now             = time();
    my $total_time_left = $self->{'total_time_limit'} - ( $now - $self->{'start_time'} );
    while ( my $next_process = shift @{ $self->{'_processes_'}{'queued'} } ) {
        if ( $total_time_left > 0 ) {
            $self->_reap_one_process();
        }
        $now             = time();
        $total_time_left = $self->{'total_time_limit'} - ( $now - $self->{'start_time'} );
        if ( $total_time_left > 0 ) {
            $self->_start_process( $next_process, $now );
        }
        else {
            &{ $next_process->{'error'} }( 'Total execution time exceeded!', @{ $next_process->{'args'} } );
        }
    }
    while ( $self->_reap_one_process() ) {

        # just loop
    }

    $self->{'running'} = 0;
    return 1;
}

sub queue {
    my $self           = shift;
    my $run_coderef    = shift;
    my $args_ar        = shift;
    my $return_coderef = shift;
    my $error_coderef  = shift;

    my $now = time();

    my $process_data = {
        'run'          => $run_coderef,
        'args'         => $args_ar,
        'return'       => $return_coderef,
        'error'        => $error_coderef,
        'pid'          => 0,
        'spool'        => '',
        'spool_length' => 0,
        'fh'           => undef,
        'start_time'   => 0,
    };

    unless ( $self->running() ) {
        $self->{'running'}                = 1;
        $self->{'_processes_'}{'running'} = [];
        $self->{'_processes_'}{'queued'}  = [];
        $self->{'start_time'}             = $now;
    }

    if ( scalar @{ $self->{'_processes_'}{'running'} } < $self->{'process_limit'} ) {
        return $self->_start_process( $process_data, $now );
    }
    else {
        push @{ $self->{'_processes_'}{'queued'} }, $process_data;
        return 1;
    }
}

sub _start_process {
    my $self         = shift;
    my $process_data = shift;
    my $now          = shift || time();

    my ( $pid, $reader_fh, $writer_fh );

    pipe( $reader_fh, $writer_fh );

    $pid = fork();
    if ( !defined $pid ) {
        close $reader_fh;
        close $writer_fh;
        if ( defined $process_data->{'error'} ) {
            &{ $process_data->{'error'} }( 'Failed to fork!', @{ $process_data->{'args'} } );
        }
        return 0;
    }
    elsif ($pid) {

        # parent
        # Non-Blocking IO
        close $writer_fh;
        Cpanel::FHUtils::Blocking::set_non_blocking($reader_fh);

        $process_data->{'start_time'} = $now;
        $process_data->{'fh'}         = $reader_fh;
        $process_data->{'pid'}        = $pid;
        my $total_time_left = $self->{'total_time_limit'} - ( $now - $self->{'start_time'} );
        my $time_left       = $self->{'process_time_limit'} < $total_time_left ? $self->{'process_time_limit'} : $total_time_left;
        $process_data->{'expires_at'} = $now + $time_left;
        push @{ $self->{'_processes_'}{'running'} }, $process_data;
        return 1;
    }
    else {

        # child
        close $reader_fh;

        if ( !$self->{'keep_stdout_open'} ) {
            open STDOUT, '>', '/dev/null' or warn "Failed to redirect STDOUT to /dev/null: $!";
        }

        # Leave stderr outputting
        #open STDERR, '>', '/dev/null';

        eval {
            my @return = &{ $process_data->{'run'} }( @{ $process_data->{'args'} } );
            print $writer_fh Cpanel::AdminBin::Serializer::Dump( \@return );
            close $writer_fh;

            exit 0;
        };

        # We only get here if the eval {} above caught an exception.
        warn;
        exit 1;
    }
}

sub _reap_one_process {
    my $self = shift;

    my $read_count;

    return 0 unless ( $self->running() );

    my $now;

    my $select_set = IO::Select->new();
    foreach my $proc ( @{ $self->{'_processes_'}{'running'} } ) {
        $select_set->add( $proc->{'fh'} );
    }

    while ( scalar @{ $self->{'_processes_'}{'running'} } ) {

        $now = time();

        for ( my $x = 0; $x <= $#{ $self->{'_processes_'}{'running'} }; $x++ ) {
            my $process_data = $self->{'_processes_'}{'running'}[$x];

            # Read the filehandle till it would block
            while ( $read_count = sysread( $process_data->{'fh'}, $process_data->{'spool'}, 4096, $process_data->{'spool_length'} ) ) {
                $process_data->{'spool_length'} += $read_count;
            }

            if ( defined $read_count ) {

                # May be closed on the other side, check for finished process
                local $?;
                my $reaped = waitpid( $process_data->{'pid'}, 1 );
                if ( $reaped == $process_data->{'pid'} ) {

                    # Reaped child
                    close $process_data->{'fh'};
                    if ( $? != 0 ) {

                        # Exited abnormally
                        if ( defined $process_data->{'error'} ) {
                            &{ $process_data->{'error'} }( 'Exited with code ' . ( $? >> 8 ) . ' and signal ' . ( $? & 127 ), @{ $process_data->{'args'} } );
                        }
                    }
                    else {

                        # Exited normally
                        my @return;

                        eval { @return = @{ Cpanel::AdminBin::Serializer::Load( $process_data->{'spool'} ) }; };
                        if ($@) {

                            # Failed to parse returned array
                            if ( defined $process_data->{'error'} ) {
                                &{ $process_data->{'error'} }( "Could not make sense of returned data ($process_data->{'spool'}) - $@", @{ $process_data->{'args'} } );
                            }
                        }
                        elsif ( defined $process_data->{'return'} ) {

                            # Parsed returned array
                            &{ $process_data->{'return'} }(@return);
                        }

                    }

                    # Remove from running array
                    splice( @{ $self->{'_processes_'}{'running'} }, $x, 1 );
                    return 1;
                }
                elsif ( $reaped == -1 ) {

                    # Child disappeared
                    if ( defined $process_data->{'error'} ) {
                        &{ $process_data->{'error'} }( 'Child disappeared during processing', @{ $process_data->{'args'} } );
                    }

                    # Remove from running array
                    splice( @{ $self->{'_processes_'}{'running'} }, $x, 1 );
                    return 1;
                }
            }

            # child needs to expire now
            if ( $process_data->{'expires_at'} <= $now ) {
                kill 'KILL', $process_data->{'pid'};

                local $?;
                waitpid( $process_data->{'pid'}, 0 );

                if ( defined $process_data->{'error'} ) {
                    &{ $process_data->{'error'} }( 'Timed Out', @{ $process_data->{'args'} } );
                }
                splice( @{ $self->{'_processes_'}{'running'} }, $x, 1 );
                return 1;

            }
        }

        # Sleep briefly
        $select_set->can_read(0.2);
    }

    return 0;
}

sub jobs_count {
    my $self = shift;
    return $self->active_count() + $self->queued_count();
}

sub active_count {
    my $self = shift;
    return scalar @{ $self->{'_processes_'}{'running'} };
}

sub queued_count {
    my $self = shift;
    return scalar @{ $self->{'_processes_'}{'queued'} };
}

sub get_operations_per_process {
    my ( $self, $total_operations ) = @_;

    require Cpanel::Math;
    return Cpanel::Math::ceil( $total_operations / $self->process_limit() );
}

#parallel map basically
sub pmap ( $code, @list ) {

    my $run_cb = sub {
        local $_ = shift;
        return $code->();
    };

    my $parallelizer = Cpanel::Parallelizer->new();

    my $lim = scalar(@list);
    $lim = $lim < 20 ? $lim : 20;
    $parallelizer->process_limit($lim);

    my @ret;
    my $ret_cb = sub {
        push( @ret, @_ );
    };
    my $err_cb = sub { };

    foreach my $x (@list) {
        $parallelizer->queue( $run_cb, [$x], $ret_cb, $err_cb );
    }
    $parallelizer->run();
    return @ret;
}

1;

__END__

=head1 NAME

Cpanel::Parallelizer

=head1 SYNOPSIS

    use Cpanel::Parallelizer;

    my $parallelizer = Cpanel::Parallelizer->new();

    $parallelizer->process_limit(20);
    $parallelizer->process_time_limit(30);
    $parallelizer->total_time_limit(300);

    my $run_coderef = sub {
       my ($number, $string) = @_;
       return ( "Process number $number", $string );
    };

    my $return_coderef = sub {
       my ($one, $two) = @_;
       print "$one -- $two\n";
    };

    my $error_coderef = sub {
        my ($error_string, @args) = @_;
        print "Encountered error: $error_string\n";
    }

    foreach my $x ( 1 .. 20 ) {
        $parallelizer->queue($run_coderef, [$x, 'rest_of_args'], $return_coderef, $error_coderef);
    }

    $parallelizer->run();

    # or, use this simplified form having default values for limits, etc

    my @output = Cpanel::Parallelizer::pmap( sub { transform($_) }, @input );

=head1 DESCRIPTION

The Cpanel::Parallelizer is a simple class for executing code simultaneously in multiple
processes.

=head2 METHODS

=over 4

=item new()

Constuctor for the Cpanel::Parallelizer object.  Optional arguments are:
    process_limit        Number of simultaneous processes
    total_time_limit     Maximum total running time: One hour by default
    process_time_limit   Maximum running time for a single child process: 30 minutes by default

=item queue($run_coderef, $args_arrayref, $return_coderef, $error_coderef)

This queues or starts a new process to handle the supplied arguments.  It does not handle any
other process management (such as reaping children.)

  $run_coderef    - This is the codereference that will be executed in the new
                    process.
  $args_arrayref  - This array reference will be fed into $run_coderef as @_
  $return_coderef - Any data that $run_coderef returns will be fed into $return_coderef
                    as @_.  $return_coderef executes within the parent process.
  $error_coderef  - This optional coderef is called when any errors are encountered
                    creating or communicating with a child process.  It is given
                    ("error message", @{$args_arrayref) as input.

=item run()

This method executes all queued processes to completion.  It must be called once all
processes are loaded into the queue for the work to be completed.

=item process_limit()

Get or set the process_limit setting

=item process_time_limit()

Get or set the process_time_limit setting

=item total_time_limit()

Get or set the total_time_limit setting

=item running()

Returns true if processes have been queued for execution.  Once run() has
been invoked, running() should return false.

=item start_time()

Returns the time that the first process was queued

=item active_count()

Returns the number of actively running processes

=item queued_count()

Returns the number of processes that are queued and not actively running

=item get_operations_per_process($operations)

get_operations_per_process divides up the operations between as many processes
as the $parallelizer is configured to run concurrently. If there are an unequal
amount of operations, the system will prefer to group more operations and use
fewer processes. This behavior is especially useful when the caller is
downloading files via HTTP as it will maximize connection reuse.

Examples:

If we have 24 operations but only 10 concurrent processes allowed,
then each process will have 3 operations, which means we will only
use 8 of the 10 maximum processes.

If we have 100 operations but only 10 concurrent processes allowed,
then each process will have 10 operations.

If we have 105 operations but only 10 concurrent processes allowed,
then each process will have 11 operations except for the last one
which will have 6.

=item pmap()

Pretty much what it sounds like.  Parallel map{}.

=back
