package Cpanel::TaskProcessors::FilemanTasks;

# cpanel - Cpanel/TaskProcessors/FilemanTasks.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

sub to_register {
    return (
        [ 'empty_user_trash',            Cpanel::TaskProcessors::EmptyUserTrash->new() ],
    );
}

{

    package Cpanel::TaskProcessors::EmptyUserTrash;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    use strict;
    use warnings;

    use Cpanel::LoadModule ();

    sub is_valid_args {

        # This method must be implemented, but since argument validation happens in
        # Cpanel::Fileman::Trash::empty_trash, there's no reason to do it here.
        return 1;
    }

    sub _do_child_task {
        my ( $self, $task )       = @_;
        my ( $user, $older_than ) = $task->args();

        Cpanel::LoadModule::load_perl_module('Cpanel::AccessIds::ReducedPrivileges');
        Cpanel::LoadModule::load_perl_module('Cpanel::Fileman::Trash');

        my $privs = Cpanel::AccessIds::ReducedPrivileges->new($user);
        return Cpanel::Fileman::Trash::empty_trash($older_than);
    }

    sub deferral_tags { return qw/empty_trash/; }
}

1;
