package Cpanel::TaskQueue::FastSpawn;

# cpanel - Cpanel/TaskQueue/FastSpawn.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use parent 'Cpanel::TaskQueue::ChildProcessor';

{

    sub process_task {
        my ( $self, @args ) = @_;

        if ( $INC{'Cpanel/QueueProcd/Global.pm'} ) {
            my ($task) = (@args);

            # Show only the command not the args
            Cpanel::QueueProcd::Global::set_status_msg( 'process - ' . $task->command() );
        }

        return $self->SUPER::process_task(@args);
    }

    # Must match Cpanel::TaskQueue::Processor except for switching
    # system to Proc::FastSpawn::spawn_open3
    sub checked_system {
        my ( $self, $args ) = @_;

        die "Argument must be a hashref." unless ref $args eq 'HASH';

        die "Missing required 'logger' argument." unless $args->{'logger'};

        for my $arg (qw( cmd )) {
            next if length $args->{$arg};
            $args->{'logger'}->throw("Missing required '$arg' argument.");
        }

        $args->{'args'} ||= [];
        $args->{'program'} = $args->{'cmd'};

        require Cpanel::SafeRun::Object;

        # TODO: ftpupdate should not require fork()/exec()
        my %args_for_saferun = %$args;
        delete $args_for_saferun{logger};
        my $run = Cpanel::SafeRun::Object->new(%args_for_saferun);
        my $rc  = $run->CHILD_ERROR();
        if ($rc) {
            my $msg = join( q< >, map { $run->$_() // () } qw( autopsy stdout stderr ) );
            $msg =~ s{ +$}{};
            $args->{'logger'}->warn($msg);
        }
        else {
            my $msg = join( q< >, map { $run->$_() // () } qw( stdout stderr ) );
            $msg =~ s{ +$}{};
            if ( length $msg ) {
                my $command = $args->{'cmd'};
                $command .= " @{$args->{'args'}}" if $args->{'args'} && ref $args->{'args'} && scalar @{ $args->{'args'} };
                $args->{'logger'}->info("“$command”: $msg");
            }
        }
        return $rc;
    }

}

1;
