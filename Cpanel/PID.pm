package Cpanel::PID;

# cpanel - Cpanel/PID.pm                           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=encoding utf-8

=head1 Summary

B<NOTE:> Check out C<Cpanel::PIDFile> for a “tighter” implementation of this.

Subclass of Cpanel::Unix::PID::Tiny with a few additional methods
to make life easier when you just want to prevent multiple executions of a script.

=head1 Usage

$pid_obj = Cpanel::PID->new({'pid_file' => '/var/run/mypidfile.pid'});

unless ($pid_obj->create_pid_file() > 0) {
  die "Couldn't create pid file.  Process is probably running already";
}

....

$pid_obj->remove_pid_file();

=cut

use base           qw(Cpanel::Unix::PID::Tiny);
use Cpanel::Logger ();

my $logger = Cpanel::Logger->new();

sub new {
    my $class   = shift;
    my $args_hr = shift;

    my $self = $class->SUPER::new($args_hr);
    if ( defined $args_hr->{'pid_file'} ) {
        $self->{'pid_file'} = $args_hr->{'pid_file'};
    }
    return bless $self, $class;
}

# Get/set pid file
sub pid_file {
    my $self     = shift || do { $logger->die('Invalid arguments'); };
    my $pid_file = shift;
    $self->{'pid_file'} = $pid_file if ( defined $pid_file );
    return $self->{'pid_file'};
}

# Returns the current pid from the pid_file or 0
sub get_current_pid {
    my $self = shift || do { $logger->die('Invalid arguments'); };

    unless ( defined $self->{'pid_file'} ) {
        $logger->die("Attempt to query pid file without specifying filename");
    }

    if ( -e $self->{'pid_file'} ) {
        if ( open my $oldpid_fh, '<', $self->{'pid_file'} ) {
            chomp( my $curpid = <$oldpid_fh> );
            close $oldpid_fh;
            return int $curpid;
        }
        else {
            $logger->warn("Pid file exists but could not be read: $!");
        }
    }
    return 0;
}

# Takes a pid number as an optional argument
# Return value is:
#   1 for success
#   0 if pid file exists and references a running process
#   -1 for any errors
sub create_pid_file {
    my $self = shift || do { $logger->die('Invalid arguments'); };
    my $pid  = shift || $$;

    unless ( defined $self->{'pid_file'} ) {
        $logger->die("Attempt to query pid file without specifying filename");
    }

    if ( my $oldpid = $self->get_current_pid() ) {
        if ( $self->is_pid_running($oldpid) ) {
            return 0;
        }
    }
    unlink $self->{'pid_file'};
    if ( open my $pid_fh, '>', $self->{'pid_file'} ) {
        print $pid_fh $pid;
        close $pid_fh;
        return 1;
    }
    else {
        $logger->warn( "Could not write " . $self->{'pid_file'} . ": $!" );
        return -1;
    }
}

# Optionally pass in PID number
# Return codes:
#   1 removed pid file successfully
#   0 pid file appears to belong to some other process and was not removed
#   -1 error
sub remove_pid_file {
    my $self = shift || do { $logger->die('Invalid arguments'); };
    my $pid  = shift || $$;

    unless ( defined $self->{'pid_file'} ) {
        $logger->die("Attempt to remove pid file without specifying filename");
    }

    if ( my $oldpid = $self->get_current_pid() ) {
        unless ( $pid == $oldpid || !$self->is_pid_running($oldpid) ) {
            return 0;
        }
    }
    unlink $self->{'pid_file'} or return -1;
    return 1;
}

1;
