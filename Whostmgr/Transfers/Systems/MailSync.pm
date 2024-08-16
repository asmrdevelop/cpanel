package Whostmgr::Transfers::Systems::MailSync;

# cpanel - Whostmgr/Transfers/Systems/MailSync.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::Systems::MailSync

=head1 DESCRIPTION

This module synchronizes mail from the source server near the end of an
account transfer. It’s a mail analogue to the streaming of home directories
(which excludes mail).

It subclasses L<Whostmgr::Transfers::Systems>.

=cut

#----------------------------------------------------------------------

use parent qw(
  Whostmgr::Transfers::Systems
);

use Cpanel::Imports;

use Cpanel::Async::MailSync ();
use Cpanel::Exception       ();
use Cpanel::PromiseUtils    ();

use constant {
    get_phase                => 99,
    get_prereq               => ['ServiceProxy'],
    get_restricted_available => 1,

    # v64 introduced API tokens.
    minimum_transfer_source_version => 64,

    # v96 introduced the cPanel endpoint for MailSync
    minimum_transfer_source_version_for_user => 96,
};

my %restore_type_application = (
    'user' => 'cpanel',
    'root' => 'whm',
);

#----------------------------------------------------------------------

=head1 METHODS

The following conform to their standard definitions in the
framework:

=over

=item * I<OBJ>->get_summary()

=cut

sub get_summary {
    return [ locale()->maketext('This copies any new mail to the local server that the remote account received during the transfer.') ];
}

=item * I<OBJ>->restricted_restore()

=cut

sub restricted_restore ($self) {
    my $opts_hr = $self->utils()->{'flags'};

    my $remote_host = $opts_hr->{'remote_host'} or die 'need remote_host!';

    my $api_token = $opts_hr->{'remote_api_token'} or do {
        $self->out( locale()->maketext( '“[_1]” lacks mail synchronization support.', $remote_host ) );
        return 1;
    };

    if ( !$opts_hr->{'stream'} ) {
        $self->out( locale()->maketext( '“[_1]” does not support streaming.', $remote_host ) );
        return 1;
    }

    my $authn_username = $opts_hr->{'remote_api_token_username'} or do {
        die 'Missing remote WHM user!';
    };

    my $application = $restore_type_application{ $opts_hr->{'restore_type'} } or do {
        Carp::confess "no application for restore type: $opts_hr->{'restore_type'}";
    };

    my $acct_promise_hr = Cpanel::Async::MailSync::sync_to_local(
        application      => $application,
        username         => $self->newuser(),
        remote_host      => $remote_host,
        remote_username  => $authn_username,
        remote_api_token => $api_token,
    );

    my @wait_promises;

    for my $acctname ( keys %$acct_promise_hr ) {
        my $acct_promise = $acct_promise_hr->{$acctname};

        my $new_promise;

        if ( $acctname =~ tr<@><> ) {
            $new_promise = $acct_promise->catch(
                sub ($why) {
                    $why = Cpanel::Exception::get_string($why);

                    $self->warn( locale()->maketext( 'The server failed to synchronize “[_1]”’s mail because an error happened: [_2]', $acctname, $why ) );
                }
            );
        }
        else {
            $new_promise = $acct_promise->catch(
                sub ($why) {
                    $why = Cpanel::Exception::get_string($why);

                    $self->warn( locale()->maketext( 'The server failed to synchronize the system account’s mail because an error happened: [_1]', $why ) );
                }
            );
        }

        push @wait_promises, $new_promise;
    }

    Cpanel::PromiseUtils::wait_anyevent(@wait_promises);

    return 1;
}

=item * I<OBJ>->unrestricted_restore()

=cut

*unrestricted_restore = *restricted_restore;

=back

=cut

1;
