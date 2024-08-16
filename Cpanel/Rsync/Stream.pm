package Cpanel::Rsync::Stream;

# cpanel - Cpanel/Rsync/Stream.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Rsync::Stream

=cut

#----------------------------------------------------------------------

use Try::Tiny;

use Cpanel::Exception    ();
use Cpanel::Exec         ();
use Cpanel::Interconnect ();
use Cpanel::Binaries     ();

our $IS_SENDER   = 1;
our $IS_RECEIVER = 0;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 receive_rsync_to_cwd( $SOCKET, $ROLE, \@RSYNC_ARGS )

This function connects rsync to an incoming rsync
connection that is connected to the other end of $SOCKET.

You must change directory to the target directory as we
explicitly force the rsync destination to be C<.> to ensure
that the incoming connection is not passing this data
directly to rsync.

=cut

sub receive_rsync_to_cwd {
    my ( $socket, $is_sender, $rsync_command_ref ) = @_;

    my @rsync_cmd = _generate_restricted_rsync_command( $is_sender, $rsync_command_ref );

    $socket->blocking(0);
    $socket->autoflush(1);

    local $^F = 1000;    #prevent cloexec on pipe
    local $!;

    my ( $parent_read_pipe, $child_read_pipe, $parent_write_pipe, $child_write_pipe );

    pipe( $parent_read_pipe, $child_write_pipe )  or die "Could not create pipe for receive_rsync_to_cwd: $!";
    pipe( $child_read_pipe,  $parent_write_pipe ) or die "Could not create pipe for receive_rsync_to_cwd: $!";

    for ( $socket, $parent_read_pipe, $child_read_pipe, $parent_write_pipe, $child_write_pipe ) {
        $_->autoflush(1);
        $_->blocking(0);
    }

    my $pid;
    try {
        $pid = Cpanel::Exec::forked(
            \@rsync_cmd,
            sub {

                close($parent_read_pipe);
                close($parent_write_pipe);

                open( STDIN,  '<&=', fileno($child_read_pipe) )  || die "Could not connect STDIN to child_read_pipe";
                open( STDOUT, '>&=', fileno($child_write_pipe) ) || die "Could not connect STDOUT to child_write_pipe";
            },
        );
    }
    catch {
        die "failed to exec rsync: " . Cpanel::Exception::get_string($_);
    };

    close($child_read_pipe);
    close($child_write_pipe);

    return Cpanel::Interconnect->new( 'handles' => [ [ $parent_read_pipe, $parent_write_pipe ], $socket ] )->connect();

}

# This removes the destination path from the rsync command
sub _generate_restricted_rsync_command {
    my ( $is_sender, $rsync_cmd ) = @_;

    my $seen_rsync;
    my @cmd;

    foreach my $arg ( @{$rsync_cmd} ) {
        if ( $arg eq 'rsync' ) {
            $seen_rsync = 1;
        }
        elsif ( $arg eq '--server' || $arg eq '--sender' ) {
            next;
        }
        elsif ( $arg eq '.' ) {
            push @cmd, $arg;
            last;
        }
        elsif ( $seen_rsync && ( $arg =~ m{^-} || $arg eq '.' ) ) {
            push @cmd, $arg;
        }
    }
    unshift @cmd, '--sender' if $is_sender;

    my $rsync_bin = Cpanel::Binaries::path('rsync');
    -x $rsync_bin or die("The system is missing the “rsync” binary.");

    return ( $rsync_bin, '--server', @cmd, '--', '.' );
}

1;
