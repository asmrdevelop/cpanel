package Cpanel::Dsync::Stream;

# cpanel - Cpanel/Dsync/Stream.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Dsync::Stream

=head1 DESCRIPTION

This module implements streaming dsync logic.

=cut

#----------------------------------------------------------------------

use Cpanel::Exception      ();
use Cpanel::Exec           ();
use Cpanel::Interconnect   ();
use Cpanel::Dovecot::Utils ();

use Try::Tiny;

#----------------------------------------------------------------------

=head1 connect( $CLIENT_SOCKET, $EMAIL_ACCOUNT )

This function starts a local dsync server process and interconnects that
process to a given $CLIENT_SOCKET, which may be either a simple OS
filehandle or a C<tie()>d filehandle, e.g., an L<IO::Socket::SSL> instance.

Note that no actual C<connect()> takes place here; however, the semantics
match up insofar as that $CLIENT_SOCKET is the dsync server process’s peer.

Note that our local dsync process can either send I<or> receive from its
peer.

=head1 SEE ALSO

F<bin/dsync_cpsrvd_client_whm> implements one way to call into this
module from the cpsrvd-client side.

=cut

sub connect ( $socket, $email_account ) {

    local $^F = 1000;    #prevent cloexec on pipe
    local $!;

    my ( $parent_read_pipe, $child_read_pipe, $parent_write_pipe, $child_write_pipe );

    # Would this be faster as a socketpair()?
    pipe( $parent_read_pipe, $child_write_pipe )  or die "Could not create pipe for receive_dsync_to_cwd: $!";
    pipe( $child_read_pipe,  $parent_write_pipe ) or die "Could not create pipe for receive_dsync_to_cwd: $!";

    for ( $socket, $parent_read_pipe, $child_read_pipe, $parent_write_pipe, $child_write_pipe ) {
        $_->autoflush(1);
        $_->blocking(0);
    }

    my $pid;
    try {
        $pid = Cpanel::Exec::forked(
            [ Cpanel::Dovecot::Utils::doveadm_bin(), 'dsync-server', '-u', $email_account ],
            sub {

                close($parent_read_pipe);
                close($parent_write_pipe);

                open( STDIN,  '<&=', fileno($child_read_pipe) )  || die "Could not connect STDIN to child_read_pipe: $!";
                open( STDOUT, '>&=', fileno($child_write_pipe) ) || die "Could not connect STDOUT to child_write_pipe: $!";
            },
        );
    }
    catch {
        die "failed to exec doveadm dsync-server: " . Cpanel::Exception::get_string($_);
    };

    close($child_read_pipe);
    close($child_write_pipe);

    return Cpanel::Interconnect->new( 'handles' => [ [ $parent_read_pipe, $parent_write_pipe ], $socket ] )->connect();

}
1;
