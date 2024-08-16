package Cpanel::TaskProcessors::SSLCleanupTasks;

# cpanel - Cpanel/TaskProcessors/SSLCleanupTasks.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

{

    package Cpanel::TaskProcessors::SSLCleanupTasks::UnsetTLS;

    use parent -norequire => 'Cpanel::TaskProcessors::SSLCleanupTasks::_Base';

    use Cpanel::LoadModule ();

    use constant {
        _ARGS_COUNT => 0,
    };

    #tested directly
    sub _do_child_task {
        my ($self) = @_;

        Cpanel::LoadModule::load_perl_module('Cpanel::Apache::TLS::Write');
        Cpanel::LoadModule::load_perl_module('Cpanel::Domain::TLS::Write');

        Cpanel::Apache::TLS::Write->new()->process_unset_tls_queue();
        Cpanel::Domain::TLS::Write->process_unset_tls_queue();

        return;
    }

    sub deferral_tags {
        return qw/httpd/;
    }

}

{

    package Cpanel::TaskProcessors::SSLCleanupTasks::AutoSSLPurgeUser;

    use parent -norequire => 'Cpanel::TaskProcessors::SSLCleanupTasks::_Base';

    use Cpanel::LoadModule ();

    use constant {
        _ARGS_COUNT => 1,
    };

    sub _do_child_task {
        my ( $self, $task ) = @_;

        my ($user) = $task->args();
        Cpanel::LoadModule::load_perl_module('Cpanel::SSL::Auto::Purge');

        return Cpanel::SSL::Auto::Purge::purge_user($user);
    }

    sub deferral_tags {
        return qw/httpd/;
    }
}

sub to_register {
    return (
        [ 'autossl_purge_user', Cpanel::TaskProcessors::SSLCleanupTasks::AutoSSLPurgeUser->new() ],
        [ 'unset_tls',          Cpanel::TaskProcessors::SSLCleanupTasks::UnsetTLS->new() ],
    );
}

#----------------------------------------------------------------------

package Cpanel::TaskProcessors::SSLCleanupTasks::_Base;

use parent 'Cpanel::TaskProcessor';

#Make all dupes clobber the older task.
*overrides = __PACKAGE__->can('is_dupe');

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::TaskProcessors::SSLCleanupTasks - Task processor for removing ssl certs from ssl storage

=head1 VERSION

This document describes Cpanel::TaskProcessors::SSLCleanupTasks version 0.0.3


=head1 SYNOPSIS

    use Cpanel::TaskProcessors::SSLCleanupTasks;

=head1 DESCRIPTION

Implement the code to remove uninstalled certs

=head1 INTERFACE

This module defines one subclass of L<Cpanel::TaskQueue::FastSpawn> and a package method.

=head2 Cpanel::TaskProcessors::SSLCleanupTasks::to_register

Used by the L<Cpanel::TaskQueue::PluginManager> to register the included classes.

=head2 Cpanel::TaskProcessors::SSLCleanupTasks::AutoSSLPurgeUser

A thin wrapper around Cpanel::SSL::Auto::Purge::purge_user that
is used to remove a user from the AutoSSL system.

=head1 CONFIGURATION AND ENVIRONMENT

Cpanel::TaskProcessors::SSLCleanupTasks assumes that the environment has been made
safe before any of the tasks are executed.

=head1 DEPENDENCIES

None

=head1 INCOMPATIBILITIES

None reported.

=head1 BUGS AND LIMITATIONS

No bugs have been reported.

=head1 AUTHOR

J. Nick Koston  C<< nick@cpanel.net >>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2016, cPanel, Inc. All rights reserved.
