package Cpanel::FastSpawn::InOut;

# cpanel - Cpanel/FastSpawn/InOut.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Proc::FastSpawn ();

use Cpanel::FHUtils::Autoflush ();

=encoding utf-8

=head1 NAME

Cpanel::FastSpawn::InOut - Spawn a child process using FastSpawn

=head1 SYNOPSIS

    use Cpanel::FastSpawn::InOut ();

    my $pid = Cpanel::FastSpawn::InOut::inout( $write, $read, '/usr/bin/perl' );

    my $pid = Cpanel::FastSpawn::InOut::inout_with_env( {'VAR1'=>'val', 'VAR2'=>'val'}, $write, $read, '/usr/bin/perl' );

=head1 DESCRIPTION

This module executes a command in a subprocess using the C<posix_spawn>
C function. This function uses the C<vfork> system call instead
of C<fork> or C<clone>. This almost completely eliminates the overhead of
forking and C<exec>ing a separate command.

=head1 “ALMOST” DROP-IN REPLACEMENT

This module is intended as an “almost” drop-in replacement
for L<Cpanel::SafeRun::InOut>.

Differences include:

=over

=item * B<!!IMPORTANT!!:> The child process is not automatically reaped,
so you’ll need either to set C<$SIG{CHLD}> to C<IGNORE> or to reap
the process manually, e.g., via C<waitpid>.

=back

=head1 FUNCTIONS

=cut

=head2 $pid = inout( $write, $read, $command, @args )

Spawn a child process and returns the PID.

Inputs are:

=over

=item * C<$write> - An auto-vivified file handle to write to the child process,
or -1 to have the child read from the parent process’s STDIN.

=item * C<$read> - An auto-vivified file handle to read from the child process,
or -1 to have the child write to the parent process’s STDOUT.

=item * C<$command> - The executable to run

=item * C<@args> - The arguments to pass to the executable.

=back

Note that the child will reuse the parent process’s STDERR.
If you want to handle STDERR yourself, see C<inout_all()>.

=cut

sub inout {
    return inout_with_env( undef, @_ );
}

=head2 $pid = inout_with_env( $env_hr, $write, $read, $command, @args )

Spawn a child process with a specified environment and returns the PID.

=over

=item * C<$env_hr> - A hashref of environment variables that the child process with start with.

=item * and the rest are as for C<inout>.

=back

=cut

sub inout_with_env {

    my @opts_kv = (
        env => $_[0],
    );

    if ( !$_[1] || ref $_[1] ) {
        push @opts_kv, stdin => \$_[1];
    }
    else {
        push @opts_kv, stdin => $_[1];
    }

    if ( !$_[2] || ref $_[2] ) {
        push @opts_kv, stdout => \$_[2];
    }
    else {
        push @opts_kv, stdout => $_[2];
    }

    return inout_all(
        @opts_kv,
        stderr  => -1,
        program => $_[3],
        args    => [ @_[ 4 .. $#_ ] ],
    );
}

=head2 $pid = inout_all(%opts)

A generalization of C<inout()> and C<inout_with_env()> to allow further
customization of the invocation.

%opts are:

=over

=item * C<program> (required)

=item * C<args> (optional, array reference)

=item * C<env> (optional, hash reference)

=item * C<stdin>, C<stdout>, C<stderr> - optional. If not given,
the closed end of a pipe will be passed, so reads will not block and
writes will EPIPE. Given values can be:

=over

=item * a filehandle that you’ll use to interact with the process

=item * a file descriptor (i.e., number) for that same filehandle

=item * a reference to an undefined value that will be auto-vivified
with a filehandle (for similar use as the previous option)

=item * a reference to an L<IO::Handle> instance (not the instance itself!)
that will serve the same purpose as the undefined-value case

=back

=back

=cut

sub inout_all (%opts) {
    if ($Cpanel::AccessIds::ReducedPrivileges::PRIVS_REDUCED) {    # PPI NO PARSE --  can't be reduced if the module isn't loaded
        die __PACKAGE__ . " cannot be used with ReducedPrivileges. Use Cpanel::FastSpawn::Object instead";
    }

    my @cmd = ( $opts{'program'} || die 'need “program”' );
    push @cmd, @{ $opts{'args'} } if $opts{'args'};

    my @fhs_to_fastspawn;

    _process_fh_arg( $opts{'stdin'}, \@fhs_to_fastspawn, 0 );

    for my $name (qw( stdout  stderr )) {
        _process_fh_arg( $opts{$name}, \@fhs_to_fastspawn, 1 );
    }

    my @fastspawn_fds;

    for my $fh (@fhs_to_fastspawn) {
        push @fastspawn_fds, ref($fh) && fileno($fh);
        if ( !length $fastspawn_fds[-1] ) {
            $fastspawn_fds[-1] = $fh;
        }
    }

    return Proc::FastSpawn::spawn_open3(
        $fastspawn_fds[0],
        $fastspawn_fds[1],
        $fastspawn_fds[2],
        $cmd[0],
        \@cmd,
        _env_to_fastspawn( $opts{'env'} ),
    );
}

sub _process_fh_arg ( $given, $fhs_ar, $is_write ) {
    if ( defined $given ) {
        if ( ref $given ) {
            my $fh;

            if ( UNIVERSAL::isa( $given, 'GLOB' ) ) {
                $fh = $given;
            }
            else {

                # We expect $given to be a reference to a “thing to be
                # vivified”: either undef, or an IO::Handle instance.

                if ($is_write) {
                    _pipe_or_die( $$given, $fh );
                }
                else {
                    _pipe_or_die( $fh, $$given );
                }

                Cpanel::FHUtils::Autoflush::enable($_) for $fh, $$given;
            }

            push @$fhs_ar, $fh;
        }
        else {

            # We expect $given to be a file descriptor
            push @$fhs_ar, $given;
        }
    }
    else {

        # $given is undef, which means to pass the open end of a
        # one-sided pipe.

        _pipe_or_die( my ( $r, $w ) );

        push @$fhs_ar, $is_write ? $w : $r;
    }

    return;
}

sub _env_to_fastspawn ($env) {
    return $env ? [ ( map { $_ . '=' . ( $env->{$_} // '' ) } keys %$env ) ] : ();
}

sub _pipe_or_die {
    pipe( $_[0], $_[1] ) or die "pipe() failed: $!";

    return;
}

1;
