package Cpanel::CLI::TransferAccounts;

# cpanel - Cpanel/CLI/TransferAccounts.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::CLI::TransferAccounts

=head1 DESCRIPTION

This module houses common logic for the account-transfer scripts.
It extends L<Cpanel::HelpfulScript>.

=cut

#----------------------------------------------------------------------

use parent qw(
  Cpanel::HelpfulScript
  Cpanel::CLI::SecretTaker
);

use IO::Prompter    ();
use Cpanel::Finally ();

use cPanel::APIClient ();

use constant _OPTIONS => (
    'host=s',
    'enqueue=s@',
    'session=s@',
);

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 ($host, $username) = I<OBJ>->parse_opts()

Returns the value of the given C<--host> and C<--user> parameters
and sanity-checks the C<--enqueue> parameters.

=cut

sub parse_opts ($self) {
    my $host = $self->getopt('host') or die $self->_help('Need “host”!');

    my $username = $self->getopt('user') or die $self->_help('Need “user”!');

    $self->_get_session_opts();
    $self->_get_enqueue_opts();

    return ( $host, $username );
}

=head2 $aborter = I<OBJ>->create_session_and_aborter( $FUNCNAME, \%ARGS )

Creates the transfer session via the WHM API v1 function named by
$FUNCNAME, with arguments %ARGS.

The return value is an opaque object that MUST remain in scope until the
transfer starts; if it falls out of scope before then the transfer session
will be aborted.

=cut

sub create_session_and_aborter ( $self, $api_funcname, $args_hr ) {
    $self->say("Creating session …");

    my %create_args = (
        %$args_hr,
        $self->_get_session_opts(),
    );

    my $create = $self->_api_or_die(
        $api_funcname,
        \%create_args,
        "create session",
    );

    my $xfer_id = $create->get_data()->{'transfer_session_id'} or do {

        # This shouldn’t happen, but just in case:
        die "$api_funcname() didn’t return a “transfer_session_id”!";
    };

    $self->say("\tDone! ID=$xfer_id");

    $self->{'xfer_id'} = $xfer_id;

    #----------------------------------------------------------------------

    my $started_ok;
    my $guard = Cpanel::Finally->new(
        sub {
            if ( !$started_ok ) {
                $self->say("Aborting transfer session …");

                $self->_api_or_die(
                    'abort_transfer_session',
                    {
                        transfer_session_id => $xfer_id,
                    },
                    "abort failed",
                );

                $self->say("\tDone.");
            }
        }
    );

    $self->{'started_ok_sr'} = \$started_ok;

    return $guard;
}

=head2 I<OBJ>->enqueue_users( $MODULE, \@USERNAMES )

Enqueues @USERNAMES for transfer via $MODULE (e.g., C<AccountRemoteRoot>).
The local username will match the original, and all C<--enqueue> options
given to the script will apply to each user.

=cut

sub enqueue_users ( $self, $module, $usernames_ar ) {
    my $xfer_id = $self->{'xfer_id'};

    my @enqueue_opts = $self->_get_enqueue_opts();

    my $is_multi = @$usernames_ar > 1;

    my $total_u = @$usernames_ar;

    for my $u ( 1 .. $total_u ) {
        my $username = $usernames_ar->[ $u - 1 ];

        if ($is_multi) {
            $self->say("Enqueuing user “$username” (#$u of $total_u) …");
        }
        else {
            $self->say("Enqueuing user “$username” …");
        }

        my $enq = $self->_api_or_die(
            'enqueue_transfer_item',
            {
                transfer_session_id => $xfer_id,
                module              => $module,
                user                => $username,
                localuser           => $username,
                @enqueue_opts,
            },
            "enqueue “$username”",
        );

        $self->say("\tDone!");
    }

    return;
}

=head2 I<OBJ>->do_transfer_and_finish()

Starts the transfer then asks whether the caller wants to tail the
newly-started session’s log.

=cut

sub do_transfer_and_finish ($self) {
    $self->say("Starting transfer …");

    $self->_api_or_die(
        'start_transfer_session',
        {
            transfer_session_id => $self->{'xfer_id'},
        },
        "start failed",
    );

    ${ $self->{'started_ok_sr'} } = 1;

    $self->say("Transfer started!");
    $self->say(q<>);

    my $assent = IO::Prompter::prompt(
        "Do you want to tail the transfer log? [Yn]",
        '-stdio',
        '-yesno',
        '-single',
        -default => 'y',
    );

    my @cmd = ( '/usr/local/cpanel/bin/view_transfer', $self->{'xfer_id'} );

    if ($assent) {
        exec @cmd;
    }
    else {
        $self->say("OK. You can view it yourself by running:");
        $self->say(q<>);
        $self->say("\t@cmd");
    }

    return;
}

sub _get_whm ($self) {
    return $self->{'_whm'} ||= cPanel::APIClient->create(
        service   => 'whm',
        transport => ['CLISync'],
    );
}

sub _get_session_opts ($self) {
    return $self->_get_kv_opts('session');
}

sub _get_enqueue_opts ($self) {
    return $self->_get_kv_opts('enqueue');
}

sub _get_kv_opts ( $self, $getopt_key ) {
    my @enqueue_opts_kv;
    if ( my $enq_ar = $self->getopt($getopt_key) ) {
        for my $enq (@$enq_ar) {
            my ( $k, $v ) = split m<=>, $enq, 2;
            if ( !length $v ) {
                die "“$enq” is malformed.\n";
            }

            push @enqueue_opts_kv, $k, $v;
        }
    }

    return @enqueue_opts_kv,;
}

sub _api_or_die ( $self, $name, $args_hr, $errlabel ) {
    my $whm = $self->_get_whm();

    my $result = $whm->call_api1( $name, $args_hr );

    for my $msg ( @{ $result->get_nonfatal_messages() } ) {
        my ( $lvl, $txt ) = @$msg;
        $self->say("\t$lvl: $txt");
    }

    if ( my $err = $result->get_error() ) {
        die "$errlabel: $err\n";
    }

    return $result;
}

1;
