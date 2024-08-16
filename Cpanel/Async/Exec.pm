package Cpanel::Async::Exec;

# cpanel - Cpanel/Async/Exec.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use experimental 'isa';

=encoding utf-8

=head1 NAME

Cpanel::Async::Exec - asynchronous C<exec(2)>

=head1 SYNOPSIS

    use AnyEvent;

    my $execer = Cpanel::Async::Exec->new();

    my ($in, $out);

    my $run = $execer->exec(
        program => '/bin/cat',
        args => [ ],    # just for demonstration purposes
        stdin => \$in,
        stdout => \$out,
    );

    syswrite $in, 'hello';

    my $cv = AnyEvent->condvar();

    $run->child_error_p()->then(
        sub { print "subprocess is done\n" }
    )->finally($cv);

    $cv->recv();

    my $got = <$out>;   # should be 'hello'

=head1 DESCRIPTION

This module C<exec(2)>s commands asynchronously. It’s similar to
modules like L<AnyEvent::Fork> (but is simpler) or
L<IO::Async::Process> (but is lighter).

This module assumes use of L<AnyEvent>.

=head1 SEE ALSO

See L<Cpanel::Async::Forker> if you want to execute Perl code in
the subprocess instead.

=cut

#----------------------------------------------------------------------

use parent qw( Cpanel::Destruct::DestroyDetector );

use AnyEvent    ();
use Promise::XS ();

use Cpanel::Async::Exec::Process ();    # PPI NO PARSE - bless()ed manually
use Cpanel::Async::Throttler     ();
use Cpanel::Exception            ();
use Cpanel::FastSpawn::InOut     ();
use Cpanel::FHUtils::Blocking    ();
use Cpanel::FHUtils::FDFlags     ();

my $_DEFAULT_PROCESS_LIMIT = 10;
my $_DEFAULT_TIMEOUT       = 3600;

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new( %OPTS )

Instantiates this class.

%OPTS are:

=over

=item * C<process_limit> - The maximum number of forked processes that the
object will create at a given time. Any tasks submitted when this many
forked processes are already in play will be deferred to a wait queue,
à la L<Cpanel::Async::Throttler>.

Defaults to 10.

=back

=cut

sub new ( $class, %opts ) {
    my $process_limit = delete $opts{'process_limit'} || $_DEFAULT_PROCESS_LIMIT;

    if (%opts) {
        my @unknown = sort keys %opts;
        die "$class: Unknown parameters: [@unknown]";
    }

    my $throttler = Cpanel::Async::Throttler->new($process_limit);

    my %self = (
        _throttler => $throttler,
    );

    return bless \%self, $class;
}

=head2 $run_obj = I<OBJ>->exec( %OPTS )

Runs a command. %OPTS are as given to L<Cpanel::FastSpawn::InOut>’s
C<inout_all()> function, as well as the following:

=over

=item * C<timeout> - optional, in seconds. Defaults to 3600.
Give 0 to indicate no timeout

=back

Any auto-vivified filehandles that this creates will be set
non-blocking.

The return is a L<Cpanel::Async::Exec::Process> instance.

=cut

sub exec ( $self, %opts ) {
    my ($canceled);

    my $deferred = Promise::XS::deferred();

    my %process_args = (
        canceled_sr => \$canceled,
        deferred    => $deferred,
    );

    my $process_obj = bless \%process_args, 'Cpanel::Async::Exec::Process';

    $self->{'_throttler'}->add(
        sub {
            if ($canceled) {
                return Promise::XS::resolved();
            }

            return $self->_exec_now( \%opts, $process_obj );
        }
    );

    return $process_obj;
}

sub _reap ( $pid, $pid_canceled_hr, $deferred ) {
    if ( !defined $pid ) {
        $deferred->resolve('256');
        return;
    }
    local $?;
    waitpid $pid, 0;

    if ( !delete $pid_canceled_hr->{$pid} ) {
        $deferred->resolve($?);
    }

    return;
}

sub _exec_now ( $self, $opts_hr, $process_obj ) {

    # This is how we detect process end without listening for SIGCHLD:
    # the read end is CLOEXEC, but the write end is non-CLOEXEC. As a
    # result, the writer will stay open until the child process ends.
    #
    # This works as long as the child process doesn’t close that
    # file descriptor .. which could happen, but generally doesn’t
    # since it’s unusual for a process to close file descriptors
    # that it doesn’t need to know about.
    #
    pipe my $r, my $w or die "pipe(): $!";
    Cpanel::FHUtils::FDFlags::set_non_CLOEXEC($w);

    # Hold onto the filehandle so Perl doesn’t close() it prematurely.
    $process_obj->{'end_rfh'} = $r;

    my $pid = Cpanel::FastSpawn::InOut::inout_all(
        %{$opts_hr}{qw( program args env stdin stdout stderr )},
    );

    # Any auto-vivified filehandles should be set non-blocking.
    for my $fh ( @{$opts_hr}{ 'stdin', 'stdout', 'stderr' } ) {
        next if !UNIVERSAL::isa( $fh, 'REF' ) || !UNIVERSAL::isa( $$fh, 'GLOB' );
        Cpanel::FHUtils::Blocking::set_non_blocking($$fh);
    }

    my $deferred    = $process_obj->{'deferred'};
    my $canceled_sr = $process_obj->{'canceled_sr'};

    # A promise that always resolves whenever the process ends,
    # even if it’s terminated.
    my $process_deferred = Promise::XS::deferred();
    $process_obj->{'process_deferred'} = $process_deferred;

    my $timer;
    my $watch;

    my $cleanup_cr = sub {
        undef $watch;
        undef $timer;
        undef $process_obj;

    };

    my $timeout = $opts_hr->{'timeout'} // $_DEFAULT_TIMEOUT;

    if ($timeout) {
        $timer = AnyEvent->timer(
            after => $timeout,
            cb    => sub {
                $process_obj->terminate();

                $cleanup_cr->();

                my @cmd = ( $opts_hr->{'program'} );
                push @cmd, @{ $opts_hr->{'args'} } if $opts_hr->{'args'};

                require Cpanel::Time::Split;
                my $timeout_str = Cpanel::Time::Split::seconds_to_locale($timeout);

                my $err = Cpanel::Exception::create( 'Timeout', 'The system terminated the execution of “[_1]” because it exceeded its allowed time ([_2]).', [ "@cmd", $timeout_str ] );

                $deferred->reject($err);
            },
        );
    }

    $watch = AnyEvent->io(
        fh   => $r,
        poll => 'r',
        cb   => sub {
            $cleanup_cr->();
            $process_deferred->resolve();

            _reap( $pid, $$canceled_sr, $deferred );
        },
    );

    $process_obj->{'pid'}      = $pid;
    $process_obj->{'watch_sr'} = \$watch;
    $process_obj->{'timer_sr'} = \$timer;

    return $process_deferred->promise();
}

1;
