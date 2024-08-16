package Cpanel::Exec;

# cpanel - Cpanel/Exec.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Exec

=head1 SYNOPSIS

    my $pid = Cpanel::Exec::forked(
        [ '/path/to/program', @arguments ],
        sub {
            $ENV{'CUSTOM_VAR'} = 'this is set right before the child’s exec()';
        },
    );

=head1 FUNCTIONS

=cut

use strict;
use warnings;

use Cpanel::Exception ();
use Cpanel::ForkAsync ();

=head2 $pid = forked( CMD_AR, BEFORE_EXEC_CR )

This implements an error-checked fork-then-exec; if either the
C<fork()> or the C<exec()> fails, the parent will throw an exception. This is
better than checking the exit status because it lets you distinguish between
when the binary exited in error and when it failed to run in the first place.

C<forked()> is B<probably> always preferable to writing out
fork..exec manually.

NOTES:

=over 4

=item * The first argument in the command arrayref is the PROGRAM.
If that argument has spaces, those spaces are interpreted as
being part of the PROGRAM. (cf.: exec { $prog } $prog, @args)
This is different from how Perl’s C<exec()> interprets this--and should
be safer.

=item * BEFORE_EXEC_CR is optional. This is where you can set C<%ENV>,
setuid, etc.

=back

=cut

sub forked {
    my ( $cmd_ar, $before_exec_cr ) = @_;

    local $!;

    #This is how we determine whether the child process's exec() fails.
    #We sysread() from this below. Anything that that returns is an error
    #from the exec(); if the sysread() returns nothing, then exec()
    #succeeded. (The exec()'d program has no access to the pipe.)
    #
    #NOTE: This is the same method that perl uses to populate $!
    #when open() to a command fails.
    #
    my ( $read_exec_err, $write_exec_err );
    {

        #Ensure that these filehandles are FD_CLOEXEC; otherwise,
        #if the caller has a high $^F set, the sysread() below will block
        #when the exec() succeeds.
        local $^F = 0;
        pipe $read_exec_err, $write_exec_err or die "pipe() failed: $!";
    }

    my $pid = Cpanel::ForkAsync::do_in_child(
        sub {
            close $read_exec_err or warn "close pipe: $!";

            $before_exec_cr->() if $before_exec_cr;

            no warnings 'exec';    ## no critic qw(ProhibitNoWarnings)

            exec( { $cmd_ar->[0] } @$cmd_ar ) or do {
                my $exec_err = $!;

                #Tell the parent about exec()'s failure.
                #This could theoretically fail, but that's exceedingly unlikely.
                syswrite( $write_exec_err, pack( 'C', 0 + $exec_err ) );

                exit $exec_err;
            };
        }
    );

    close $write_exec_err or warn "close pipe: $!";

    my $exec_error;
    if ( sysread $read_exec_err, $exec_error, 1 ) {

        # Block because the child should be reapable “soon”
        # if it isn’t already.
        waitpid $pid, 0;

        local $! = unpack 'C', $exec_error;    #To get error stringification
        die Cpanel::Exception::create( 'IO::ExecError', [ error => $!, path => $cmd_ar->[0] ] );
    }

    close $read_exec_err or warn "close pipe: $!";

    return $pid;
}

1;
