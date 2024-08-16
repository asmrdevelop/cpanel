package Cpanel::TaskProcessors::LocaleTasks;

# cpanel - Cpanel/TaskProcessors/LocaleTasks.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

my %bool_parms = qw(--quiet 1 --verbose 1 --force 1 --clean 1 --user-check 1 --clean-stale-locales 1 --clean-stale-locales=exit 1);

{

    package Cpanel::TaskProcessors::BuildLocale;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub overrides {
        my ( $self, $new, $old ) = @_;

        return   if $new->command() ne $old->command();
        return 1 if $self->is_dupe( $new, $old );

        my $n_args = _arg_desc($new);
        my $o_args = _arg_desc($old);

        # If new is all locales and stronger command, override.
        return 1 if !@{ $n_args->{'locales'} } && $n_args->{'strength'} >= $o_args->{'strength'};

        # If old is all locales, don't override
        return if !@{ $o_args->{'locales'} } || $n_args->{'strength'} < $o_args->{'strength'};

        foreach my $l ( @{ $o_args->{'locales'} } ) {
            return unless grep { $l eq $_ } @{ $n_args->{'locales'} };
        }

        # If we get here, new is a strict superset of old. So we can override
        return 1;
    }

    sub _arg_desc {
        my ($task) = @_;
        my @args   = $task->args();
        my $desc   = { 'strength' => 0, 'locales' => [] };
        $desc->{'strength'} = 1 if grep { '--force' eq $_ } @args;
        $desc->{'strength'} = 2 if grep { '--clean' eq $_ } @args;
        $desc->{'locales'}  = [ map { /^--locale=(.*)$/ } @args ];
        return $desc;
    }

    sub is_valid_args {
        my ( $self, $task ) = @_;

        my @args = $task->args();

        return 1 if 0 == @args;

        for my $arg (@args) {
            next if exists $bool_parms{$arg};

            next if $arg =~ /^--locale=/;
            return;
        }

        return 1;
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;
        local $SIG{'CHLD'} = 'DEFAULT';

        # once this module is localized we'll need to detach/attach around the
        # checked system() call in order to avoid write tie fail due to parent
        # still holding a read tie to the same cdb via $locale
        # $locale->cpanel_detach_lexicon(); # if $locale is what we're
        # rebuilding

        $self->checked_system(
            {
                'logger' => $logger,
                'name'   => 'build_locale_databases script',
                'cmd'    => '/usr/local/cpanel/bin/build_locale_databases',
                'args'   => [ $task->args() ],
            }
        );

        # once this module is localized we'll need to detach/attach around the
        # checkedsystem() call in order to avoid write tie fail due to parent
        # still holding a read tie to the same cdb via $locale
        # $locale->cpanel_attach_lexicon(); # if $locale is what we're
        return;
    }

    sub deferral_tags {
        my ($self) = @_;
        return qw/locale_db/;
    }
}

sub to_register {
    return (
        [ 'build_locale_databases', Cpanel::TaskProcessors::BuildLocale->new() ],
    );
}

1;
__END__

=head1 NAME

Cpanel::TaskProcessors::LocaleTasks - Task to build locale database

=head1 SYNOPSIS

    use Cpanel::TaskProcessors::LocaleTasks;

=head1 DESCRIPTION

Implement the code for the I<build_lcaole_databases> Task.

=head1 INTERFACE

This module defines two subclass of L<Cpanel::TaskQueue::FastSpawn> and a package method.

=head2 Cpanel::TaskProcessors::LocaleTasks::to_register

Used by the L<Cpanel::TaskQueue::PluginManager> to register the included classes.

=head2 Cpanel::TaskProcessors::BuildLocale

This class implements the I<build_locale_databases> Task. Implemented methods are:

=over 4

=item $proc->overrides( $new, $old )

Determines if the C<$new> task overrides the C<$old> task. Override for this
class is defined as follows:

If the new task has exactly the same command and args, it overrides the old
task.

If the new task has the same command and no arguments, it overrides the old task.

Otherwise, return false.

=item $proc->is_valid_args( $task )

Returns true if the task has appropriate arguments for this command.

=back

=head1 CONFIGURATION AND ENVIRONMENT

Cpanel::TaskProcessors::ApacheTasks assumes that the environment has been made
safe before any of the tasks are executed.

=head1 DEPENDENCIES

None.

=head1 INCOMPATIBILITIES

None reported.

=head1 BUGS AND LIMITATIONS

No bugs have been reported.

=head1 AUTHOR

G. Wade Johnson  C<< wade@cpanel.net >>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2009, cPanel, Inc. All rights reserved.
