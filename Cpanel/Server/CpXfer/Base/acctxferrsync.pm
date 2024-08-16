package Cpanel::Server::CpXfer::Base::acctxferrsync;

# cpanel - Cpanel/Server/CpXfer/Base/acctxferrsync.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::CpXfer::Base::acctxferrsync - homedir streaming via rsync

=head1 DESCRIPTION

This CpXfer module implements the core logic for streaming a user home
directory over CpXfer via rsync.

All callers must pass the C<rsync_arguments> parameter, a JSON-encoded
list of strings to pass to the C<rsync> command. Ordinarily these arguments
come from the client rsync invocation and are first given to the command
named as the C<--rsh> command-line argument.

This module subclasses L<Cpanel::Server::CpXfer>.

A normal workflow for calling into this function is:

=over

=item * A command like C<rsync --rsh /path/to/script $username: $destdir>
runs. (Note the C<:> after the username!) You may not need to give a
“real” username; it’ll depend on the specific endpoint you call. Even
if you don’t give a username, though, you still need to give C<:>;
otherwise rsync won’t know that it needs to do a file transfer at all.

(NB: rsync understands C<$username:> to mean that $username is the
remote hostname. But since we give C<--rsh>, rsync doesn’t actually make
a connection; it just hands $username off to the script. The fact that
$username is not a hostname thus doesn’t affect what rsync does at all.

=item * The script will receive as arguments: the username, then an
C<rsync> command (as more arguments, not a space-joined string) to run
on the remote. That command, in its list form, is what goes into
C<rsync_arguments>.

=item * The script should call the relevant acctxferrsync module then
proxy all traffic between STDIN/STDOUT and the cpsrvd socket.

=back

See this module’s subclasses for specific implementation details.

=cut

#----------------------------------------------------------------------

use parent qw( Cpanel::Server::CpXfer );

use Cpanel::Exception     ();
use Cpanel::JSON          ();
use Cpanel::Rsync::Stream ();

sub _BEFORE_HEADERS {
    my ( $self, $form_ref ) = @_;

    local $@;
    $self->{'_rsync_arguments'} = eval {
        my $json = $form_ref->{'rsync_arguments'} // die "Need “rsync_arguments” (JSON)!\n";

        my $parsed = Cpanel::JSON::Load($json);

        if ( 'ARRAY' ne ref($parsed) ) {
            die "“rsync_arguments” must be an array, not: $parsed\n";
        }

        if ( !@$parsed ) {
            die "“rsync_arguments” may not be empty.\n";
        }

        $parsed;
    };

    if ( !$self->{'_rsync_arguments'} ) {
        my $err = $@;
        if ( ref $@ ) {
            $err = $@->to_string_no_id();
        }
        chomp $err;

        die Cpanel::Exception::create_raw( 'cpsrvd::BadRequest', $err );
    }

    my $homedir = $self->_get_homedir($form_ref);

    $self->get_server_obj()->memorized_chdir($homedir) || $self->get_server_obj()->internal_error("Failed to memorized_chdir() to $homedir: $!");

    return;
}

sub _AFTER_HEADERS {
    my ($self) = @_;

    my $socket = $self->get_socket();

    # Cpanel::Rsync::Stream expects this to be there. If it’s already
    # there nothing is affected.
    unshift @{ $self->{'_rsync_arguments'} }, 'rsync';

    Cpanel::Rsync::Stream::receive_rsync_to_cwd( $socket, $Cpanel::Rsync::Stream::IS_SENDER, $self->{'_rsync_arguments'} );

    return;
}

1;
