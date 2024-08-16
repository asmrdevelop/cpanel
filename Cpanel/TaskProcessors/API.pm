package Cpanel::TaskProcessors::API;

# cpanel - Cpanel/TaskProcessors/API.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 NAME

Cpanel::TaskProcessors::API

=cut

{

    package Cpanel::TaskProcessors::API::VerifyAPISpecFiles;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub is_valid_args {
        my ( $self, $task ) = @_;
        return 0 == $task->args;
    }

    sub deferral_tags {
        return qw(api);
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        $self->checked_system(
            {
                'logger' => $logger,
                'name'   => 'verify_api_spec_files',
                'cmd'    => '/usr/local/cpanel/scripts/verify_api_spec_files',
                'args'   => [],
            }
        );

        return;
    }

}

=head2 to_register

verify_api_spec_files - Runs /scripts/verify_api_spec_files to rebuild the API info used by the API Shell.

=cut

sub to_register {
    return (
        [ 'verify_api_spec_files', Cpanel::TaskProcessors::API::VerifyAPISpecFiles->new() ],
    );
}

1;
