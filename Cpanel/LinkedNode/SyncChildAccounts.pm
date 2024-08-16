package Cpanel::LinkedNode::SyncChildAccounts;

# cpanel - Cpanel/LinkedNode/SyncChildAccounts.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::SyncChildAccounts

=head1 SYNOPSIS

    Cpanel::LinkedNode::SyncChildAccounts::sync_child_accounts(
        usernames => [ 'joan', 'billy' ],
        output_obj => $cpanel_output_instance,
    );

=head1 DESCRIPTION

This is the backend logic behind F<scripts/sync_child_accounts>.

=cut

#----------------------------------------------------------------------

use Try::Tiny;

use Promise::XS;

use Cpanel::Imports;

use Cpanel::iContact::Icons            ();
use Cpanel::LinkedNode::Worker::WHM    ();
use Cpanel::LinkedNode::Worker::GetAll ();
use Cpanel::PromiseUtils               ();
use Cpanel::Config::LoadCpUserFile     ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 sync_child_accounts( %OPTS )

This implements F<scripts/sync_child_accounts>’s functionality
in an interface that’s reusable from other Perl code.

%OPTS are:

=over

=item * C<usernames>

=item * C<output_obj> - A L<Cpanel::Output> instance.

=back

=cut

sub sync_child_accounts (%opts) {
    my ( $output, $usernames_ar ) = @opts{ 'output_obj', 'usernames' };

    my %hostname_api;

    my @promises;

    # This is a separate variable in case multiple actions ever
    # happen per user.
    my $user_count = 0;

    for my $username (@$usernames_ar) {

        my $cpuser_obj = Cpanel::Config::LoadCpUserFile::load_or_die($username);
        my @worker_hrs = Cpanel::LinkedNode::Worker::GetAll::get_all_from_cpuser($cpuser_obj);

        # Ignore non-distributed accounts.
        next if !@worker_hrs;

        $user_count++;

        my %alias_workloads;
        push @{ $alias_workloads{ $_->{'alias'} } }, $_->{'worker_type'} for @worker_hrs;

        Cpanel::LinkedNode::Worker::WHM::do_on_all_user_nodes(
            username      => $username,
            remote_action => sub ($cfg) {
                my $alias    = $cfg->alias();
                my $hostname = $cfg->hostname();

                $hostname_api{$hostname} ||= $cfg->get_async_remote_api();

                push @promises, $hostname_api{$hostname}->request_whmapi1(
                    'PRIVATE_set_child_workloads',
                    {
                        username => $username,
                        workload => $alias_workloads{$alias},
                    },
                )->then(
                    sub ($resp) {
                        my $msg;

                        if ( $resp->get_data()->{'updated'} ) {
                            $msg = locale->maketext('Updated.');
                        }
                        else {
                            $msg = locale->maketext('No update needed.');
                        }

                        $output->success(
                            Cpanel::iContact::Icons::get_icon('success') . " $username: $msg",
                        );
                    },
                )->catch(
                    sub ($why) {
                        require Cpanel::Exception;
                        $output->error(
                            Cpanel::iContact::Icons::get_icon('error') . " $username: " . Cpanel::Exception::get_string($why),
                        );
                    },
                );
            },
        );
    }

    if (@promises) {
        $output->info( locale()->maketext( "Synchronizing [quant,_1,distributed account,distributed accounts] …", $user_count ) );

        Cpanel::PromiseUtils::wait_anyevent(@promises);
    }

    return;
}

1;
