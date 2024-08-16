package Cpanel::Team::Queue;

# cpanel - Cpanel/Team/Queue.pm                    Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Autodie       ();
use Cpanel::Exception     ();
use Cpanel::SafeFile      ();
use Cpanel::SafeDir::Read ();

my $team_queue_dir = '/var/cpanel/team_queue';

=encoding utf-8

=head1 NAME

Cpanel::Team::Queue

=head1 DESCRIPTION

Module to manage team task queue

Team queue is comprised of task files located in /var/cpanel/team_queue/ with
the following file name format:

 /var/cpanel/team_queue/<epoch>_<team-owner>_<team-user>

 <epoch> Unix Time Epoch, number of seconds since January 1, 1970 UTC
 <team-owner> Team-owner account name
 <team-user> Team-user account name

If more than one job exists for the same team-user to be executed at the same
time the last one submitted will overwrite the previous one.

Task file format:

 <bash-command>

Example file named '1669067647_ibm_jim' contains one line:

 /usr/local/cpanel/bin/expire_team_user ibm jim

Must call new() first to ensure that team queue directory is set up.  Then any
other methods can be called.

 use Cpanel::Team::Queue();

 my $team_q_obj = Cpanel::Team::Queue->new();
 my $worked     = $team_q_obj->queue_task( $expire_date, $team_owner, $team_user, $cmd );
 my $did_it     = $team_q_obj->dequeue_task($task_file);
 my @tasks      = $team_q_obj->find_tasks( $team_owner, $team_user );
 my $command_ok = $team_q_obj->allow_command($command);
 my @tasks      = $team_q_obj->list_queue();
 $team_q_obj->print_queue();

=head1 METHODS

=over

new -- Create team queue object.

    Makes sure team queue directory exists and configured correctly.

    RETURNS: 1 on success

    ERRORS
        All failures are fatal.
        Fails if cannot access or create team queue directory.

    EXAMPLE
        my $team_q_obj = Cpanel::Team::Queue->new();

=back

=cut

sub new {
    my ($class) = @_;

    Cpanel::Autodie::mkdir_if_not_exists( $team_queue_dir, 0700 );

    my $self = {
        queue_dir => $team_queue_dir,
    };
    return bless $self, $class;
}

=head1 METHODS

=over

dequeue_task -- Remove task(s) from queue.

    Removes tasks from queue that match certain criteria

    RETURNS: 1 on success

    ERRORS
        All failures are fatal.
        Fails if task cannot be found.
        Fails if parameters are invalid.
        Fails if cannot remove task.

    EXAMPLES
        my $status = $team_q_obj->dequeue_task($file); # Dequeue based on filename.
        my $status = $team_q_obj->dequeue_task( $team_owner, $team_user ); # Dequeue all for a specific team-user.
        my $status = $team_q_obj->dequeue_task( $epoch, $team_owner, $team_user ); # Dequeue a specific task.

=back

=cut

sub dequeue_task {
    my ( $self, @args ) = @_;

    my @files;
    if ( @args == 3 ) {
        my ( $epoch, $team_owner, $team_user ) = @args;
        push @files, $self->{queue_dir} . "/${epoch}_${team_owner}_$team_user";
    }
    elsif ( @args == 2 ) {
        my ( $team_owner, $team_user ) = @args;
        opendir DH, $self->{queue_dir} or die Cpanel::Exception::create( 'InvalidParameter', 'Cannot open team queue directory “[_1]”.', [ $self->{queue_dir} ] );
        @files = map { "$self->{queue_dir}/$_" } grep { /^\d+_${team_owner}_$team_user$/ } readdir DH;
        closedir DH;
    }
    elsif ( @args == 1 ) {
        push @files, shift @args;
    }
    else {
        die Cpanel::Exception::create( 'InvalidParameter', "Invalid or Missing required parameters" );
    }

    my $ok = 1;
    if ( @files > 0 ) {
        foreach my $file (@files) {
            if ( -e $file ) {
                unlink $file or do { $ok = 0 };
            }
        }
    }
    return $ok;
}

=head1 METHODS

=over

queue_task -- Adds task to team queue.

    Creates team task and puts in team queue.

    Note that queuing a task where the epoch is in the past is acceptable.

    RETURNS: 1 on success

    ERRORS
        All failures are fatal.
        Fails if epoch is not valid.
        Fails if team-owner does not exist.
        Fails if team-user does not exist.
        Fails if task command is not allowed.
        Fails if cannot create team task file.

    EXAMPLE
        my $status = $team_q_obj->queue_task( $epoch, $team_owner, $team_user, $command );

=back

=cut

sub queue_task {
    my ( $self, $epoch, $team_owner, $team_user, $cmd ) = @_;

    if ( !allow_command($cmd) ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'Command “[_1]” is not allowed.', [$cmd] );
    }
    $cmd =~ s/\s+$//;

    if ( !$epoch || $epoch !~ /^\d{10}$/ ) {    # This RE will reject dates after Sat Nov 20 17:46:39 2286 UTC.
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid [asis,UNIX] epoch timestamp.', [$epoch] );
    }

    my $task_filename = "$self->{queue_dir}/${epoch}_${team_owner}_$team_user";
    my $file_lock     = Cpanel::SafeFile::safeopen( my $fh, ">", $task_filename );
    if ( !$file_lock ) {
        die Cpanel::Exception::create( 'IO::FileOpenError', [ path => $task_filename, error => $!, mode => '>' ] );
    }
    print $fh $cmd, "\n";
    return Cpanel::SafeFile::safeclose( $fh, $file_lock );
}

=head1 METHODS

=over

allow_command -- Checks to see if command is a known command.

    Looks for known commands, rejecting unknown or questionable commands, including compound commands.

    RETURNS:
        The value associated with the command.
        Currently it returns the notification class associated with the command.

    ERRORS
        None.

    EXAMPLE
        my $notification_class = $team_q_obj->allow_command($command);

=back

=cut

sub allow_command {
    my $command = shift;

    return 0 if !defined $command;

    # Reject compound or convoluted commands.
    if ( $command =~ /[;&|(){}`!]/ ) {
        return 0;
    }

    my %allowed_command_list = (    # Add new commands that are allowed here.
        '/usr/local/cpanel/bin/expire_team_user' => 'Team::TeamUserExpired',
    );

    foreach my $allowed_command ( keys %allowed_command_list ) {
        if ( $command =~ /^\s*$allowed_command\b/ ) {
            return $allowed_command_list{$allowed_command};
        }
    }
    return 0;
}

=head1 METHODS

=over

find_tasks -- Returns list of files/tasks associated with a given team-owner and team_user.

    Reads team queue directory and returns list of tasks/files belonging to a given team-owner and team-user.

    RETURNS: List of files in execution order

    ERRORS
        All failures are fatal.
        Fails if cannot read team queue directory.

    EXAMPLE
        my @task_files = $team_q_obj->find_tasks( $team_owner, $team_user );

=back

=cut

sub find_tasks {
    my ( $self, $team_owner, $team_user ) = @_;

    return map { "$self->{queue_dir}/$_" } grep { /_${team_owner}_$team_user$/ } Cpanel::SafeDir::Read::read_dir( $self->{queue_dir} );
}

=head1 METHODS

=over

list_queue -- Returns list of files/tasks in the queue.

    Reads team queue directory and returns list of files.

    RETURNS: List of of files in execution order

    ERRORS
        All failures are fatal.
        Fails if cannot read team queue directory.

    EXAMPLE
        my @task_files = $team_q_obj->list_queue();

=back

=cut

sub list_queue {
    my @tasks = Cpanel::SafeDir::Read::read_dir( shift->{queue_dir} );
    return ( sort @tasks );
}

=head1 METHODS

=over

print_queue -- Prints details of team queue contents, in order of execution.

    Reads and prints team queue in pretty format like this:

    Date                     Owner  User  Command
    Mon Dec 12 05:07:48 2022 ibm,   bob   command: /usr/local/cpanel/bin/expire_team_user ibm bob
    Fri Dec 16 11:00:27 2022 ibm,   carl  command: /usr/local/cpanel/bin/expire_team_user ibm carl
    Thu Aug 10 09:22:18 2023 bwc,   john  command: /usr/local/cpanel/bin/expire_team_user bwc john

    RETURNS: 1 on success

    ERRORS
        All failures are fatal.
        Fails if cannot read queue or tasks.

    EXAMPLE
        my $status = $team_q_obj->print_queue();

=back

=cut

sub print_queue {
    my ( $self, $fh ) = @_;
    $fh = defined $fh ? $fh : \*STDOUT;

    my @task_files = $self->list_queue();

    if ( @task_files == 0 ) {
        print $fh "Team task queue is empty.\n";
        return 1;
    }

    my @date_column    = ('Date');
    my @owner_column   = ('Owner');
    my @user_column    = ('User');
    my @command_column = ('Command');
    my $owner_size     = 5;             # For determining column width.
    my $user_size      = 4;
    my $cmd_size       = 0;

    foreach my $task_file (@task_files) {
        my ( $date, $team_owner, $team_user ) = split /_/, $task_file;
        $owner_size = length $team_owner if length $team_owner > $owner_size;
        $user_size  = length $team_user  if length $team_user > $user_size;
        $date       = localtime $date;
        my $task_path = "$self->{queue_dir}/$task_file";
        open my $fh_cmd, '<', $task_path
          or die Cpanel::Exception::create( 'IO::FileOpenError', [ path => $task_path, error => $!, mode => '<' ] );
        undef $/;
        my $cmd = <$fh_cmd>;
        chop $cmd               if $cmd =~ /\n*$/;
        $cmd_size = length $cmd if length $cmd > $cmd_size;
        close $fh_cmd;
        push @date_column,    $date;
        push @owner_column,   $team_owner;
        push @user_column,    $team_user;
        push @command_column, $cmd;
    }

    my $first_time = 0;
    my $date_size  = length $date_column[1];
    foreach my $date (@date_column) {
        printf $fh "%-${date_size}s  %-${owner_size}s  %-${user_size}s  %-s\n",
          $date, shift @owner_column, shift @user_column, shift @command_column;
        printf $fh "%s  %s  %s  %s\n",    # Fancy underlines
          "=" x length $date_column[1], "=" x $owner_size, "=" x $user_size, "=" x $cmd_size if $first_time++ <= 0;
    }

    return 1;
}

1;
