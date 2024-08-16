package Cpanel::TaskProcessors::RubyTasks;

# cpanel - Cpanel/TaskProcessors/RubyTasks.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

{

    package Cpanel::TaskProcessors::RubyTasks::WriteGemRC;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    use Try::Tiny;
    use Cpanel::LoadModule ();

    sub overrides {
        my ( $self, $new, $old ) = @_;
        my $is_dupe = $self->is_dupe( $new, $old );
        return $is_dupe;
    }

    sub is_valid_args {
        my ( $self, $task ) = @_;
        my $numargs = scalar $task->args();
        return 0 if $numargs != 1;
        my ($user) = $task->args();
        Cpanel::LoadModule::load_perl_module('Cpanel::AcctUtils::Account');
        return 1 if Cpanel::AcctUtils::Account::accountexists($user);
        return 0;
    }

    sub _do_child_task {
        my ( $self, $task ) = @_;
        my ($user) = $task->args();

        Cpanel::LoadModule::load_perl_module('Cpanel::Debug');
        Cpanel::LoadModule::load_perl_module('Cpanel::RoR::Gems');
        Cpanel::LoadModule::load_perl_module('Cpanel::AccessIds');
        Cpanel::LoadModule::load_perl_module('Cpanel::PwCache');
        my $uhomedir = Cpanel::PwCache::gethomedir($user);
        try {
            Cpanel::AccessIds::do_as_user_with_exception(
                sub {
                    local $ENV{'HOME'} = $uhomedir;
                    return Cpanel::RoR::Gems::write_gemrc($uhomedir);
                },
                $user
            );
        }
        catch {
            Cpanel::Debug::log_warn($_);
        };

        return 1;
    }
}

sub to_register {
    return (
        [ 'write_gemrc', Cpanel::TaskProcessors::RubyTasks::WriteGemRC->new() ],

    );
}

1;
__END__

=head1 NAME

Cpanel::TaskProcessors::RubyTasks - Task processor for Ruby

=head1 VERSION

This document describes Cpanel::TaskProcessors::RubyTasks version 0.0.3


=head1 SYNOPSIS

    use Cpanel::TaskProcessors::RubyTasks;

=head1 DESCRIPTION

Implement the code for the I<write_gemrc> task. These
are not intended to be used directly.

=head1 INTERFACE

This module defines one subclass of L<Cpanel::TaskQueue::FastSpawn> and a package method.

=head2 Cpanel::TaskProcessors::RubyTasks::to_register

Used by the L<Cpanel::TaskQueue::PluginManager> to register the included classes.

=head2 Cpanel::TaskProcessors::RubyTasks::WriteGemRC

This class creates a .gemrc file for a user
Implemented methods are:

=over 4

=item $proc->overrides( $new, $old )

Determines if the C<$new> task overrides the C<$old> task. Override for this
class is defined as follows:

If the new task has exactly the same command and args, it overrides the old
task.

Otherwise, return false.

=item $proc->is_valid_args( $task )

Returns true if the task has no arguments or only the C<user> argument.

=back

=head1 CONFIGURATION AND ENVIRONMENT

Cpanel::TaskProcessors::RubyTasks assumes that the environment has been made
safe before any of the tasks are executed.

=head1 INCOMPATIBILITIES

None reported.

=head1 BUGS AND LIMITATIONS

No bugs have been reported.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2016, cPanel, Inc. All rights reserved.
