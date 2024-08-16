package Cpanel::CommandStream::Handler::tardownload;

# cpanel - Cpanel/CommandStream/Handler/tardownload.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent (
    'Cpanel::CommandStream::Handler',
);

use Cpanel::LinkedNode::Privileged::Configuration ();
use Promise::XS                                   ();

use Cpanel::LinkedNode::Convert::TarWithNode ();

# Sample input
# {"class":"tardownload", "id":1, "hostname":"10-1-35-202.cprapid.com", "username":"root", "tls_verification":"on", "remote_directory":"/root", "local_directory":"/tmp/foo", paths:["*"], "api_token": "777O7SO7P7Z3KIZLMVFMUVN53J9H5XQ" }

use constant {
    VERIFY_TLS => 0,
    REQ_ARGS   => [
        qw(
          local_directory remote_directory paths
          hostname username api_token tls_verification
        )
    ]
};

sub _run ( $self, $req_hr, $courier, $completion_d ) {    ## no critic qw(ProhibitManyArgs)

    state %tls_verified_value = (
        on  => 1,
        off => 0,
    );

    my ( $why_bad, $tls_verified );

    {
        my @missing = grep { !defined $req_hr->{$_} } REQ_ARGS()->@*;
        if (@missing) {
            $why_bad = "Must supply " . join( ", ", @missing );
        }
        else {
            $tls_verified = $req_hr->{'tls_verification'};

            $tls_verified = $tls_verified_value{$tls_verified} // do {
                $why_bad = "Bad “tls_verification”: $tls_verified";
            };
        }

        if ($why_bad) {
            $courier->send_response( 'bad_arguments', { why => $why_bad } );
            $completion_d->resolve();
            return;
        }
    }

    my $node_obj = Cpanel::LinkedNode::Privileged::Configuration->new(
        'hostname'     => $req_hr->{hostname},
        'username'     => $req_hr->{username},
        'api_token'    => $req_hr->{api_token},
        'tls_verified' => $tls_verified,
    );

    # receive_p() to be a “gentle” refactor of receive():
    my $p = Cpanel::LinkedNode::Convert::TarWithNode::receive_p(
        tar => {
            directory       => $req_hr->{local_directory},
            setuid_username => 'root',
        },
        websocket => {
            node_obj => $node_obj,
            module   => 'TarBackup',
            query    => {
                directory       => $req_hr->{'remote_directory'},
                setuid_username => 'root',
                %{$req_hr}{'paths'},
            },
        },

        on_start => sub {
            $courier->send_response('started');
        },
        on_warn => sub ($text) {
            $courier->send_response( 'warn', { content => $text } );
        },
    )->then(
        sub { $courier->send_response('done') },
        sub ($why) { $courier->send_response( 'failed', { why => $why } ) },
    )->finally( sub { $completion_d->resolve() } );

    return;
}

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::CommandStream::Handler::tardownload - Tar Download Module

=head1 SYNOPSIS

Open up a web socket session with C<websocat> where C<10-1-34-66.cprapid.com> is the parent's hostname

    websocat wss://10-1-34-66.cprapid.com:2087/websocket/CommandStream \
      -k \
      -H'Authorization: whm root:PARENT TOKEN'

Paste this into the terminal where C<10-1-35-202.cprapid.com> is the remote hostname, and the API token is a root token on that host

    {"class":"tardownload", "id":1, "hostname":"10-1-35-202.cprapid.com", "username":"root", "tls_verification":"on", "remote_directory":"/root", "local_directory":"/tmp/foo", "paths":["*"], "api_token": "REMOTE_TOKEN" }

=head1 PARAMETERS

Besides the C<class> and C<id>—which are part of every CommandStream
message—we expect the following:

=over 4

=item hostname

The remove hostname you wish to connect to.

=item username

The username you wish to connect as.

=item api_token

The remote API token to use for the purposes of authentication.

=item tls_verification

Either C<on> or C<off>.

=item remote_directory

The directory on the remote server from which to send.

=item local_directory

The local directory where to receive/create.

=item paths

An array of relative paths to transfer.

=back

=head1 MESSAGES

=over 4

=item started

This message is sent when the transfer is started (i.e.,
remote connection is made and local tar is started).

=item warn

This message is sent with warnings. It includes a C<content> string.

=item done

This message is sent on completion.

=item failed

This message is sent on failure, or in the lack of completion.
It includes a C<why> string.

=back
