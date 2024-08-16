package Cpanel::UserTasksCore::Task;

# cpanel - Cpanel/UserTasksCore/Task.pm            Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Unix::PID::Tiny      ();
use Cpanel::UserTasksCore::Utils ();
use File::Path::Tiny             ();

use Simple::Accessor qw{
  subsystem
  action
  args
  exclusive
  path

  _module
  _pid_dir
  _pid_file
  _fork
};

=encoding utf8

=head1 NAME

Cpanel::UserTasksCore::Task

=head1 SYNOPSIS

    Cpanel::UserTasksCore::Task->new();

=head1 DESCRIPTION

C<Cpanel::UserTasksCore::Task> internal representation of a single task.

=cut

# builders

sub _build_args      { return {} }
sub _build_exclusive { return 0; }
sub _build__fork     { return 1; }    # mainly used for unit tests to disable the forking process

sub _build_path {
    return Cpanel::UserTasksCore::Utils::queue_dir();
}

sub _build__module ($self) {
    return load_module( $self->subsystem );
}

# methods

=head1 METHODS

=head2 $obj = I<CLASS>->adopt( { ... data ... } )

Converts the passed-in hashref to a I<CLASS> instance.

=cut

sub adopt ( $class, $ref ) {
    return bless $ref, $class;
}

=head2 $self->printable_name

A friendly printable name for the task.
This is used to set $0 and to log some informations for the task.

=cut

sub printable_name ($self) {
    return eval {
        join( ' - ', map { $_ // '' } "uid:$>", $self->subsystem, $self->action );
    } // '';
}

=head2 $self->run(%opts)

Run the task.

Available options are:

=over

=item pre

A CodeRef used a a pre hook run before running the task.

=item post

A CodeRef used a a post hook run after running the task.


Note:
The function 'run' returns:
* pid: when run in background (default behavior)
* -1: when run in foreground
* undef or 0: when we cannot run yet the task

It should die in any other cases to ensure the queue is not locked.

=back

=cut

sub run ( $self, %opts ) {

    my $module = $self->_module or die qq[Failed to load module: $@];
    my $action = $self->action  or die qq[Action not defined];

    die qq[Action $action is missing from $module] unless $module->can($action);

    # check for the PID file
    if ( $self->exclusive ) {    # can only run a single task of that type at the same time
        return if $self->_is_already_running();
    }

    my $name = $self->printable_name;

    my $run = sub {              # running the task

        local $0 = qq[$0 - $name];

        # Try to claim the pid file.
        if ( my $pid_file = $self->_pid_file ) {
            my $upid    = Cpanel::Unix::PID::Tiny->new();
            my $got_pid = $upid->pid_file($pid_file);
        }

        # pre-hook before running the task
        if ( my $pre = $opts{pre} ) {
            $pre->($self);
        }

        # run the task here...
        $module->$action( $self->args );

        # post-hook
        if ( my $post = $opts{post} ) {
            $post->($self);
        }

        return;
    };

    if ( $self->_fork == 0 ) {
        $run->();
        return -1;
    }

    # always run the task in a detached process
    my $pid = fork;
    die qq[Failed to fork to run task '$name': $!\n] unless defined $pid;

    # parent
    return $pid if $pid > 0;

    # kid
    local $SIG{TERM} = sub {
        my $msg = qq[SIGTERM detected from $$ - $0];
        say $msg;
        exit 143;
    };
    local $SIG{PIPE} = sub {
        my $msg = qq[SIGPIPE detected from $$ - $0];
        say $msg;
        exit 141;
    };

    my $ok = eval { $run->(); 1 };
    say $@ unless $ok;
    exit( $ok ? 0 : 1 );
}

# internal helpers

sub _build__pid_file ($self) {

    # our unique ID to only run one task at the same time
    my $name = $self->printable_name;
    if ( my $id = $self->exclusive ) {
        $name .= "-$id" if $id ne '1';
    }

    $name =~ s{^uid:\d+}{}a;
    $name =~ s{[^a-zA-Z-0-9:]+}{-}g;
    $name =~ s{-+}{-}g;
    $name =~ s{^-}{}g;

    Carp::confess("No name for task...") unless length $name;

    return sprintf( "%s/%s.pid", $self->_pid_dir(), $name );
}

sub _build__pid_dir ($self) {
    my $dir = sprintf( "%s/%s", $self->path, "pids" );

    if ( !-d $dir ) {
        File::Path::Tiny::mk($dir) or die "Could not create dir $dir: $!\n";
    }

    return $dir;
}

sub _is_already_running ($self) {
    my $pid_file = $self->_pid_file;
    return unless length $pid_file;

    return 1 if Cpanel::Unix::PID::Tiny->new()->is_pidfile_running($pid_file);

    return;
}

=head2 load_module( $module )

Load a 'Cpanel::UserTasks::$module'.

=cut

sub load_module ($mod) {

    return unless length $mod;

    my $module = "Cpanel::UserTasks::$mod";
    eval {
        my $mod_file = ( $module =~ s~::~/~gr );
        require "$mod_file.pm";    ## no critic (RequireBarewordIncludes)
    };

    return if $@;
    return $module;
}

sub TO_JSON {
    return { %{ $_[0] } };
}

1;

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2023, cPanel, Inc.  All rights reserved.  This code is
subject to the cPanel license.  Unauthorized copying is prohibited.

=cut

1;
