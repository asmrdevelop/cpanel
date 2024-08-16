package Cpanel::CommandStream::Handler::mailsync;

# cpanel - Cpanel/CommandStream/Handler/mailsync.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::CommandStream::Handler::mailsync

=head1 DESCRIPTION

This class implements handler logic for C<mailsync> CommandStream requests.

This class extends L<Cpanel::CommandStream::Handler>.

=head1 WORKFLOW

=over

=item * The request contains a C<hostname>, which is the remote host from
which mail will be retrieved.

=item * The request contains an C<api_token>, which is the API token to
use to authenticate againt the remote host.

Note that it is currently presumed that the API token is associated with
the “root” user.

=item * The request contains a C<username>, which is the user whose email
accounts will be synchronized with the remote

=item * For each email account that will be synchronized (including the
system account), a C<start> message is sent. It will contain the C<name>
of the account to be synchronized.

=item * Once all C<start> messages are sent, an empty C<all_started>
message is sent.

=item * For each email account that a synchronization is attempted, a
C<success> or C<failure> is sent. Both will have a C<name>.

If the result is a C<failure> the message will include a C<why> explaining
the failure.

=back

Sample message flow (request then responses):

    {"class":"mailsync", "id":0, "hostname":"the.mail.node", "username":"maily", "api_token":"M79UUDPOWF128S1HR5KB28SRI4LG1ZND"}
      {"class":"start", "id":"0", "name":"maily"}
      {"class":"start", "id":"0", "name":"themail@maily.tld"}
      {"class":"all_started", "id":"0"}
      {"class":"success", "id":"0", "name":"maily"}
      {"class":"failure", "id":"0", "name":"themail@maily.tld", "why":"haha"}

=head1 FAILURES

C<bad_arguments> contains a C<why> that explains why the given
arguments don’t work.

=cut

use parent (
    'Cpanel::CommandStream::Handler',
);

use Cpanel::Async::MailSync ();

sub _run ( $self, $req_hr, $courier, $completion_d ) {    ## no critic qw(ManyArgs) - mis-parse

    my @missing = grep { !$req_hr->{$_} } qw( username hostname api_token );
    if (@missing) {
        _fail_bad_arguments( $courier, "Missing: @missing" );
        $completion_d->resolve();
        return;
    }

    my ( $username, $hostname, $api_token ) = @{$req_hr}{qw( username hostname api_token )};

    my $user_promises_hr = Cpanel::Async::MailSync::sync_to_local(
        application      => 'whm',
        username         => $username,
        remote_username  => 'root',
        remote_host      => $hostname,
        remote_api_token => $api_token,
    );

    my @promises;

    for my $name ( keys %$user_promises_hr ) {
        $courier->send_response( 'start', { name => $name } );

        push @promises, $user_promises_hr->{$name}->then(
            sub {
                $courier->send_response( 'success', { name => $name } );
            },
            sub ($why) {

                # We need $why to be unblessed since it’s being serialized:
                $why = "$why";

                $courier->send_response( 'failure', { name => $name, why => $why } );
            },
        );
    }

    $courier->send_response('all_started');

    Promise::XS::all(@promises)->finally( sub { $completion_d->resolve() } );

    return;
}

sub _fail_bad_arguments ( $courier, $why ) {
    $courier->send_response( 'bad_arguments', { why => $why } );

    return;
}

1;
