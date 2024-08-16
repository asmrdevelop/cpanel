package Cpanel::UserTasks::VersionControl;

# cpanel - Cpanel/UserTasks/VersionControl.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::VersionControl::Cache      ();
use Cpanel::VersionControl::Deployment ();

=head1 FUNCTIONS

=head2 Cpanel::UserTasks::VersionControl::create()

Create a repository.

=cut

sub create {
    my ( $class, $args ) = @_;

    if ( defined $args->{'repository_root'} ) {
        my $vc = Cpanel::VersionControl::Cache::retrieve( $args->{'repository_root'} );
        $vc->create( $args->{'log_file'} );
    }

    return;
}

=head2 Cpanel::UserTasks::VersionControl::deploy()

Perform a deployment.

=cut

sub deploy {
    my ( $class, $args ) = @_;

    Cpanel::VersionControl::Deployment->new(%$args)->execute();

    return;
}

1;
