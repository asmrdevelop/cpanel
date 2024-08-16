#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - bin/rsync-user-homedir.pl               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package scripts::rsync_user_homedir;

use strict;
use warnings;

use Cpanel::BinCheck::Lite ();
use autodie;

=encoding utf-8

=head1 DESCRIPTION

This script exemplifies the client-side functionality of
end classes of L<Cpanel::Server::CpXfer::Base::acctxferrsync>.

=head1 USAGE (INTERNAL TO L<rsync(1)>)

B<IMPORTANT:> You aren’t meant to call this script directly; L<rsync(1)>
calls it via its C<--rsh> parameter.

For the sake of completeness, though, this script’s arguments are:

For cPanel:

    rsync-user-homedir.pl --cpanel [--insecure] <--apitoken-fd=# | --apitoken=...> <hostname> <username> <rsyncargs..>

For WHM:

    rsync-user-homedir.pl --whm [--insecure] <--apitoken-fd=# | --apitoken=...> --homedir-user=<username> <hostname> <token_username> <rsyncargs..>

Note that the API token, for security purposes, B<MUST> be passed via
file descriptor in production code.

Also note that, in both cases, all positional parameters other than
C<E<lt>hostnameE<gt>> will come from rsync.

=head1 REAL-USAGE EXAMPLES

Below are examples of how you’ll actually give this script to L<rsync(1)>.

The following …

    rsync --archive --rsh '/usr/local/cpanel/scripts/rsync-user-homedir.pl --cpanel --apitoken=OF24KGWQS9Q8SWI6Y5PNJJHLMBY3UX6Z localhost' theusername: /where/to

… will back up C<theusername>’s home directory contents to F</where/to>.
It will authenticate to C<localhost> via the given cPanel API token.

Here is an example of WHM usage:

    rsync --archive --rsh '/usr/local/cpanel/scripts/rsync-user-homedir.pl --whm --homedir-user=theuser --apitoken-fd=5 example.com' superman: /where/to

Note the additional C<--homedir-user>; this is the user whose home directory
will be backed up. C<superman>’s given WHM API token is how we will
authenticate to WHM on the remote server C<example.com>.

The C<--insecure> flag tolerates TLS handshake errors (e.g., from
self-signed or invalid certificates). As in L<curl(1)>, you may alias
this flag as C<-k>.

=head1 SEE ALSO

F<t/support/rsync_cpsrvd_client.pl> exemplifies how to do this via the
WHM endpoint exclusively and assumes that there is a root WHM access hash.
(WHM access hashes were a forerunner to API tokens.)

=cut

#----------------------------------------------------------------------

use parent qw( Cpanel::HelpfulScript );

use IO::Socket::SSL  ();
use Cpanel::JSON::XS ();

use Cpanel::HTTP::QueryString ();
use Cpanel::Services::Ports   ();

# It’s curious that CPAN doesn’t seem to have anything to do this.
use Cpanel::Interconnect ();

use constant _OPTIONS => (
    'cpanel',
    'whm|whostmgr',
    'insecure|k',
    'homedir-user=s',
    'apitoken-fd=i',
    'apitoken=s',
);

use constant _ACCEPT_UNNAMED => 1;

Cpanel::BinCheck::Lite::check_argv();

__PACKAGE__->new(@ARGV)->run() if !caller;

sub run {
    my ($self) = @_;

    my ( $hostname, $username, @rsync_cmd ) = $self->getopt_unnamed();

    if ( !$hostname ) {
        die $self->help('Need a hostname and a username!');
    }
    elsif ( !$username ) {
        die $self->help('Need a username for the API token!');
    }
    elsif ( !@rsync_cmd ) {
        die $self->help('Need an rsync command/arguments!');
    }

    my ( $app, $port, $remote_user );

    if ( $self->getopt('cpanel') ) {
        if ( $self->getopt('whm') ) {
            die $self->help('Give either --cpanel or --whm, not both.');
        }

        $app  = 'cpanel';
        $port = $Cpanel::Services::Ports::SERVICE{'cpanels'};
    }
    elsif ( $self->getopt('whm') ) {
        $app  = 'whm';
        $port = $Cpanel::Services::Ports::SERVICE{'whostmgrs'};

        $remote_user = $self->getopt('homedir-user') // do {
            die $self->help('WHM requires a --homedir-user.');
        };
    }
    else {
        die $self->help('Give --cpanel or --whm.');
    }

    my $token;

    if ( my $fd = $self->getopt('apitoken-fd') ) {
        if ( length $self->getopt('apitoken') ) {
            die $self->help('Do not give --apitoken with --apitoken-fd.');
        }

        open my $rfh, '<&=', $fd or die "open(<&=$fd): $!";

        local $/;
        $token = readline $rfh;
    }
    else {
        $token = $self->getopt('apitoken');

        if ( length $token ) {
            warn "XXX SECURITY ALERT: Using API token from the command line.\n";
        }
    }

    if ( !length $token ) {
        die $self->help('Give an API token.');
    }

    my $query = Cpanel::HTTP::QueryString::make_query_string(
        ( $remote_user ? ( username => $remote_user ) : () ),
        rsync_arguments => Cpanel::JSON::XS::encode_json( \@rsync_cmd ),
    );

    my $path_query = "/cpxfer/acctxferrsync?$query";

    my $req = join(
        "\r\n",
        "GET $path_query HTTP/1.0",
        "Authorization: $app $username:$token",
        q<>,
        q<>,
    );

    my $cl = _get_socket(
        $hostname, $port,
        ( $self->getopt('insecure') ? ( SSL_verify_mode => 0 ) : () ),
    );

    syswrite( $cl, $req );

    my $response = do { local $/ = "\r\n\r\n"; <$cl> };

    if ( $response !~ m{^HTTP.*? 2} ) {
        print STDERR "*** ERROR ***:\n$response";
        local $/;
        die readline($cl);
    }

    Cpanel::Interconnect->new( 'handles' => [ $cl, [ \*STDIN, \*STDOUT ] ] )->connect();

    return;
}

sub _get_socket {
    my ( $hostname, $port, @extra_args ) = @_;

    return IO::Socket::SSL->new(
        PeerHost => $hostname,
        PeerPort => $port,
        @extra_args,
    ) || die "cannot connect: $IO::Socket::SSL::SSL_ERROR: $! ($@)";
}

1;
