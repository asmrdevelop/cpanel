package Whostmgr::Accounts::Remove::Cleanup::WorkerNodes;

# cpanel - Whostmgr/Accounts/Remove/Cleanup/WorkerNodes.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::LinkedNode::Worker::GetAll ();

=encoding utf-8

=head1 NAME

Whostmgr::Accounts::Remove::Cleanup::WorkerNodes

=head1 SYNOPSIS

    Whostmgr::Accounts::Remove::Cleanup::WorkerNodes::clean_up( \%cpuser )

=head1 DESCRIPTION

Account removal’s worker node cleanup logic, broken into a separate module
for more straightforward testing.

=head1 FUNCTIONS

=head2 clean_up( \%CPUSER_DATA )

Deletes user accounts on remote worker nodes.

%CPUSER_DATA is from, e.g., L<Cpanel::Config::LoadCpUserData>.

Remote account removals are noted as C<warn()>ings. The only exceptions
that this will throw are, e.g., module load failures.

Returns nothing.

=cut

#----------------------------------------------------------------------

sub clean_up ($cpuser_data) {
    local $@;

    my %alias_done;

    # NOTE: When/if a single account ever has multiple worker nodes,
    # we may want to remove the remote accounts in parallel rather than
    # in series. For now, though, we keep it simple.

    for my $worker_hr ( Cpanel::LinkedNode::Worker::GetAll::get_aliases_and_tokens_from_cpuser($cpuser_data) ) {
        require Cpanel::LinkedNode;

        my $alias = $worker_hr->{'alias'};

        next if $alias_done{$alias};

        $alias_done{$alias} = 1;

        warn if !eval {
            my $conf_obj = Cpanel::LinkedNode::get_linked_server_node(
                alias => $alias,
            );

            my $api = $conf_obj->get_remote_api();

            my $res = $api->request_whmapi1(
                'removeacct',
                {
                    user => $cpuser_data->{'USER'},
                },
            );

            die $res->get_error() if $res->get_error();

            1;
        };
    }

    return;
}

1;
