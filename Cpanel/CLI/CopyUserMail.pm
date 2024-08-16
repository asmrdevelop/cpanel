package Cpanel::CLI::CopyUserMail;

# cpanel - Cpanel/CLI/CopyUserMail.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::CLI::SyncUserMail

=head1 SYNOPSIS

See subclass scripts.

=head1 DESCRIPTION

This is the backend for scripts that sync user mail with a remote.

=cut

#----------------------------------------------------------------------

use parent (
    'Cpanel::HelpfulScript',
    'Cpanel::CLI::SecretTaker',
);

use Cpanel::Imports;

use Cpanel::Async::MailSync ();
use Cpanel::iContact::Icons ();
use Cpanel::PromiseUtils    ();

use constant _OPTIONS => (
    'mode=s',
);

use constant {
    _ACCEPT_UNNAMED => 1,
};

my %mode_sync_fn = (
    tolocal  => 'sync_to_local',
    toremote => 'sync_to_remote',
);

#----------------------------------------------------------------------

=head1 METHODS

=head2 I<OBJ>->run()

Runs this script.

=cut

sub run ($self) {
    my $mode = $self->getopt('mode') || do {
        my @accepted = sort keys %mode_sync_fn;
        die $self->help( locale()->maketext( 'Provide “[_1]” ([list_or_quoted,_2]).', '--mode', \@accepted ) );
    };

    my $sync_fn = $mode_sync_fn{$mode} || do {
        my @accepted = sort keys %mode_sync_fn;
        die $self->help( locale()->maketext( '“[_1]” must be [list_or_quoted,_2].', '--mode', \@accepted ) );
    };

    my ( $host, $username ) = $self->getopt_unnamed();

    die $self->help( locale()->maketext('Provide a hostname and a username.') ) if grep { !length $_ } ( $host, $username );

    my $token = $self->get_secret(
        $self->_get_token_phrase( $host, $username ),
        -echo => '*',
    );

    my $user_promises_hr = Cpanel::Async::MailSync->can($sync_fn)->(
        application      => $self->_APPLICATION(),
        username         => $username,
        remote_username  => $self->_get_remote_username($username),
        remote_host      => $host,
        remote_api_token => $token,
    );

    my $count = keys %$user_promises_hr;

    my $out = $self->get_output_object();

    $out->info( locale()->maketext( 'Copying [quant,_1,mailbox,mailboxes] …', $count ) );

    my %icon = map { $_ => Cpanel::iContact::Icons::get_icon($_) } (
        'success',
        'error',
    );

    for my $name ( keys %$user_promises_hr ) {

        $user_promises_hr->{$name} = $user_promises_hr->{$name}->then(
            sub {
                $out->success("$icon{'success'} OK: $name");
            },
            sub ($why) {
                $out->error("$icon{'error'} ERROR: $name - $why");
            },
        );
    }

    Cpanel::PromiseUtils::wait_anyevent( values %$user_promises_hr );

    return;
}

1;
