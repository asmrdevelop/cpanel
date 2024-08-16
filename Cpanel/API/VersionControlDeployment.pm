package Cpanel::API::VersionControlDeployment;

# cpanel - Cpanel/API/VersionControlDeployment.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception                             ();
use Cpanel::VersionControl::Cache                 ();
use Cpanel::VersionControl::Deployment::DB        ();
use Cpanel::VersionControl::Deployment::UserTasks ();

our %API = (
    _needs_feature => 'version_control',
);

=head1 SUBROUTINES

=head2 Cpanel::API::VersionControlDeployment::create()

Create a deployment for a VersionControl repository.

=cut

sub create {
    my ( $args, $result ) = @_;

    my $repo_root = $args->get_length_required('repository_root');
    my $vc        = Cpanel::VersionControl::Cache::retrieve($repo_root);
    if ( !$vc ) {
        $result->error( '“[_1]” is not a valid “[_2]”.', $repo_root, 'repository_root' );
        return;
    }

    if ( $vc->deployable() ) {
        my $ut = Cpanel::VersionControl::Deployment::UserTasks->new();

        my ($log_file) = $vc->log_file('deploy');
        my $dep = $ut->add(
            'subsystem' => 'VersionControl',
            'action'    => 'deploy',
            'args'      => {
                'repository_root' => $vc->{'repository_root'},
                'log_file'        => $log_file,
            }
        );

        $dep->{'sse_url'} = $ut->get_sse_url( $dep->{'task_id'}, $dep->{'log_path'} );
        $result->data($dep);
    }

    return 1;
}

=head2 Cpanel::API::VersionControlDeployment::retrieve()

Retrieve records for all present and past deployments.

=cut

sub retrieve {
    my ( $args, $result ) = @_;

    my $db = Cpanel::VersionControl::Deployment::DB->new();
    $result->data( $db->retrieve() );

    return 1;
}

=head2 Cpanel::API::VersionControlDeployment::delete()

Remove database records and log files for the given deployment ID.

=cut

sub delete {
    my ( $args, $result ) = @_;

    my $deploy_id = $args->get_length_required('deploy_id');

    my $db      = Cpanel::VersionControl::Deployment::DB->new();
    my $element = $db->retrieve($deploy_id);

    if ( !defined $element ) {
        die Cpanel::Exception::create(
            'InvalidParameter',
            '“[_1]” is not a valid “[_2]”.',
            [ $deploy_id, 'deploy_id' ]
        );
    }

    unlink( $element->{'log_path'} ) or do {
        die Cpanel::Exception::create(
            'IO::UnlinkError',
            [ 'path' => $element->{'log_path'}, 'error' => $! ]
        ) unless $!{'ENOENT'};
    };
    $db->remove($deploy_id);

    return 1;
}

1;
