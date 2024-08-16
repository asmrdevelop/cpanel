package Cpanel::TaskProcessors::ServerTasks;

# cpanel - Cpanel/TaskProcessors/ServerTasks.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

{

    package Cpanel::TaskProcessors::ServerTasks::SetupNameServer;

    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub overrides {
        my ( $self, $new, $old ) = @_;
        my $is_dupe = $self->is_dupe( $new, $old );
        return $is_dupe;
    }

    sub is_valid_args {
        my ( $self, $task ) = @_;
        my $numargs = scalar $task->args();
        return 0 if $numargs != 1;
        my ($server) = $task->args();
        return 0 if !$server || $server !~ /^(bind|powerdns|disabled)$/;
        return 1;
    }

    sub _do_child_task {
        my ( $self, $task ) = @_;
        my ($ns) = $task->args();
        return set_nameserver($ns);
    }

    sub set_nameserver {
        my ($ns) = @_;

        require Cpanel::NameServer::Utils::Enabled;
        return 1 unless $ns ne Cpanel::NameServer::Utils::Enabled::current_nameserver_type();

        require Cpanel::SafeRun::Object;
        my $run = Cpanel::SafeRun::Object->new( 'program' => '/usr/local/cpanel/scripts/setupnameserver', 'args' => [$ns] );

        if ( $run->CHILD_ERROR() ) {

            #Send it to the log!
            print STDERR $run->stdout() . $run->stderr() . $run->autopsy() . "\n";
            return 0;
        }

        return 1;
    }
}

sub to_register {
    return (
        [ 'setupnameserver', Cpanel::TaskProcessors::ServerTasks::SetupNameServer->new() ],
    );
}

1;
__END__


=head1 NAME

Cpanel::TaskProcessors::ServerTasks

=head2 DESCRIPTION

Essentially a matroshka like all the TaskProcessors, it contains other modules.  In this case, only one -- SetupNameServer.

=head1 SYNOPSIS

    require Cpanel::ServerTasks;
    Cpanel::ServerTasks::queue_task( ['ServerTasks'], "setupnameserver bind" );

=head1 Cpanel::TaskProcessors::ServerTasks::SetupNameServer

=head2 to_register()

To be honest, not really sure why these aren't defined as constants so I don't have to document this for POD coverage.
This probably could be defined in the parent module for 99% of use cases.

=head2 overrides()

Makes sure the tasks-dedup correctly.  Not sure why this isn't the default in the parent module.

=head2 is_valid_args()

Check that we have passed a valid nameserver as the argument.

=head2 set_nameserver($ns)

Does the actual work of switching the nameserver as directed.
