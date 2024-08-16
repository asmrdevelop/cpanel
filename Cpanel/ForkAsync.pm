package Cpanel::ForkAsync;

# cpanel - Cpanel/ForkAsync.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception ();

#Using precedent from SafeRun::InOut and SafeRun::Simple...
my $DEFAULT_ERROR_CODE = 127;    #EKEYEXPIRED

our $quiet   = 0;
our $no_warn = 0;

=head1 NAME

Cpanel::ForkAsync

=head1 SYNOPSIS

  use Cpanel::ForkAsync ();

  my $child_pid = Cpanel::ForkAsync::do_in_child( sub {
      long_running_operation() or die "Exit with error code";

      # automatically exit(0) on success or with error code when it dies
      #   no need to add an extra `exit` call here

      return;
  } );

=head1 DESCRIPTION

Perform an operation in a child process asynchronously.

=head1 FUNCTIONS

=head2 do_in_child(CODEREF, ...)

Given a coderef (CODEREF) and zero or more arguments to be passed into the code
ref when executed, launch a child process that will run the code. This function
returns immediately after launching the child and returns the pid of the child.
The caller is responsible for properly waiting on the child.

This function prevents child process from "escaping" its execution block,
which can happen if the fork() is within an eval{} and the child die()s.

A coderef passed to this function will *always* exit() when it's done.

NOTE: The coderef always runs in scalar context. That shouldn't matter,
though, since the return value is thrown away.

NOTE: This currently does NOT override $SIG{__DIE__}. (Should it?)

=cut

sub do_in_child {
    my ( $code, @args ) = @_;

    local ( $!, $^E );
    my $pid = fork();

    die Cpanel::Exception::create( 'IO::ForkError', [ error => $! ] ) if !defined $pid;

    if ( !$pid ) {
        local $@;

        if ( !eval { $code->(@args); 1 } ) {
            my $err    = $@;
            my $io_err = 0 + $!;
            _print($err) unless $quiet;
            exit( $io_err || $DEFAULT_ERROR_CODE );
        }

        exit 0;
    }

    return $pid;
}

=head2 do_in_child_quiet(CODEREF, ...)

The same as do_in_child, but disables error output in the case that the child process
throws an exception. This is useful if the error is already being captured and communicated
back to the parent somehow (as with Cpanel::ForkSync), making the output to STDERR redundant.

=cut

sub do_in_child_quiet {
    my ( $code, @args ) = @_;
    local $quiet = 1;
    return do_in_child( $code, @args );
}

=head1 SEE ALSO

Cpanel::ForkSync

Cpanel::SafeRun::Object

=cut

sub _print {
    my ($msg) = @_;

    warn $msg unless $no_warn;
    print STDERR $msg;

    return;
}

1;
