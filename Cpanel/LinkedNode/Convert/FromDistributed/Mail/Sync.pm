package Cpanel::LinkedNode::Convert::FromDistributed::Mail::Sync;

# cpanel - Cpanel/LinkedNode/Convert/FromDistributed/Mail/Sync.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Convert::FromDistributed::Mail::Sync

=head1 SYNOPSIS

    Cpanel::LinkedNode::Convert::FromDistributed::Mail::Sync::sync(
        username => 'john',
        hostname => 'the.mail.server',
        api_token => 'THEROOTAPITOKENXHBHJBHHDS',
        output_obj => $cpanel_output_instance,
    );

=head1 DESCRIPTION

This module implements mail syncing for conversions from distributed-mail
configurations.

=head1 SEE ALSO

F<scripts/sync_user_mail_as_root> is handy for one-off syncing.

=cut

#----------------------------------------------------------------------

use Cpanel::Async::MailSync ();
use Cpanel::PromiseUtils    ();

use constant _REQ_ARGS => (
    'username',
    'hostname',
    'api_token',
    'output_obj',
);

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 sync(%OPTS)

Syncs the mail from the remote server to the local server.

%OPTS are:

=over

=item * C<username> - The name of the user whose mail to sync.

=item * C<hostname> - The name of the remote host to contact.

=item * C<api_token> - A C<root> API token to access the remote host.

=item * C<output_obj> - A L<Cpanel::Output> instance where messages
should go.

=back

Nothing is returned.

NB: This B<blocks> until it finishes. Failures are reported to
C<output_obj>; this function should never throw other than for
internal problems (e.g., missing argument).

=cut

sub sync (%opts) {
    my @missing = grep { !length $opts{$_} } _REQ_ARGS();
    die "need: @missing" if @missing;

    my $user_promises_hr = Cpanel::Async::MailSync::sync_to_local(
        application      => 'whm',
        username         => $opts{'username'},
        remote_username  => 'root',
        remote_host      => $opts{'hostname'},
        remote_api_token => $opts{'api_token'},
    );

    my $out = $opts{'output_obj'};

    my @promises;

    for my $name ( keys %$user_promises_hr ) {
        push @promises, $user_promises_hr->{$name}->then(
            sub {
                $out->info("$name: OK");
            },
            sub ($why) {
                $out->error("$name: $why");
            },
        );
    }

    Cpanel::PromiseUtils::wait_anyevent(@promises);

    return;
}

1;
