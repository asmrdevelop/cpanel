package Cpanel::TaskProcessors::PerlTasks;

# cpanel - Cpanel/TaskProcessors/PerlTasks.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

{

    package Cpanel::TaskProcessors::PerlTasks::install_locallib_loginprofile;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        $self->checked_system(
            {
                'logger' => $logger,
                'name'   => 'install_locallib_loginprofile',
                'cmd'    => '/usr/local/cpanel/bin/install_locallib_loginprofile',
            }
        );
        return;
    }

}

sub to_register {
    return ( [ 'install_locallib_loginprofile', Cpanel::TaskProcessors::PerlTasks::install_locallib_loginprofile->new() ] );
}

1;
__END__

=head1 NAME

Cpanel::TaskProcessors::PerlTasks - Task processor for running some Perl maintenance

=head1 VERSION

This document describes Cpanel::TaskProcessors::PerlTasks version 0.0.1


=head1 SYNOPSIS

    use Cpanel::TaskProcessors::PerlTasks;

=head1 DESCRIPTION

Implement the code for the I<install_locallib_loginprofile> Tasks. These are not intended to be used directly.

=head1 INTERFACE

This module defines one subclass of L<Cpanel::TaskQueue::FastSpawn> and a package method.

=head2 Cpanel::TaskProcessors::PerlTasks::to_register

Used by the L<cPanel::TaskQueue::PluginManager> to register the included classes.

=head2 Cpanel::TaskProcessors::PerlTasks::install_locallib_loginprofile

This is a thin wrapper around install_locallib_loginprofile

=head1 INCOMPATIBILITIES

None reported.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2019, cPanel, L.L.C All rights reserved.
