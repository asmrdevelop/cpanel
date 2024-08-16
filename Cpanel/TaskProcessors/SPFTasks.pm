package Cpanel::TaskProcessors::SPFTasks;

# cpanel - Cpanel/TaskProcessors/SPFTasks.pm     Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

{

    package Cpanel::TaskProcessors::SPFTasks::UpdateAllUsersSPFRecords;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        require Cpanel::SPF::Update;
        Cpanel::SPF::Update::update_all_users_spf_records();

        return;
    }

}

sub to_register {
    return ( [ 'update_all_users_spf_records', Cpanel::TaskProcessors::SPFTasks::UpdateAllUsersSPFRecords->new() ] );
}

1;
__END__

=head1 NAME

Cpanel::TaskProcessors::SPFTasks - Task processor for running some SPF maintenance

=head1 VERSION

This document describes Cpanel::TaskProcessors::SPFTasks version 0.0.1


=head1 SYNOPSIS

    use Cpanel::TaskProcessors::SPFTasks;

=head1 DESCRIPTION

Implement the code for the I<update_all_users_spf_records> Tasks. These are not intended to be used directly.

=head1 INTERFACE

This module defines one subclass of L<Cpanel::TaskQueue::FastSpawn> and a package method.

=head2 Cpanel::TaskProcessors::SPFTasks::to_register

Used by the L<cPanel::TaskQueue::PluginManager> to register the included classes.

=head2 Cpanel::TaskProcessors::SPFTasks::update_all_users_spf_records

This is a thin wrapper around Cpanel::SPF::Update::update_all_users_spf_records

=head1 INCOMPATIBILITIES

None reported.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2018, cPanel, L.L.C All rights reserved.
