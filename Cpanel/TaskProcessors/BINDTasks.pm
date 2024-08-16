package Cpanel::TaskProcessors::BINDTasks;

# cpanel - Cpanel/TaskProcessors/BINDTasks.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

{

    package Cpanel::TaskProcessors::BINDTasks::RNDCQueue;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    use constant RNDC_RECONFIG_COMMAND         => 'reconfig';
    use constant RNDC_RELOAD_ALL_ZONES_COMMAND => 'reload';

    sub deferral_tags {
        return qw/rndc/;
    }

    sub is_valid_args {
        my ( $self, $task ) = @_;

        my $arg_count = scalar $task->args();
        return 1 if $arg_count == 0;

        return undef;
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        require Cpanel::DNSLib::Find;
        my $rndc_path = Cpanel::DNSLib::Find::find_rndc();
        if ( !$rndc_path ) {
            die "The system could not locate “rndc”.";
        }

        my %seen;
        my @rndc_commands;
        require Cpanel::DnsUtils::RNDCQueue::Harvester;
        Cpanel::DnsUtils::RNDCQueue::Harvester->harvest(
            sub {
                my ($cmd) = @_;
                return if $seen{$cmd}++;    # no dupes
                if ( $cmd ne RNDC_RECONFIG_COMMAND && $cmd ne RNDC_RELOAD_ALL_ZONES_COMMAND ) {
                    push @rndc_commands, $cmd;
                }
                return;
            }
        );

        # If we are reloading all zones we can remove all the other reloads
        if ( $seen{ RNDC_RELOAD_ALL_ZONES_COMMAND() } ) {
            @rndc_commands = grep { index( $_, RNDC_RELOAD_ALL_ZONES_COMMAND ) != 0 } @rndc_commands;
            unshift @rndc_commands, RNDC_RELOAD_ALL_ZONES_COMMAND;
        }

        # Reconfigs must always come before reloads
        if ( $seen{ RNDC_RECONFIG_COMMAND() } ) {
            unshift @rndc_commands, RNDC_RECONFIG_COMMAND;
        }

        foreach my $cmd (@rndc_commands) {
            $self->checked_system(
                {
                    'logger' => $logger,
                    'name'   => 'rndc',
                    'cmd'    => $rndc_path,
                    'args'   => [ split( m{ }, $cmd ) ],
                }
            );
        }
        return;
    }
}

sub to_register {
    return (
        [ 'rndc_queue', Cpanel::TaskProcessors::BINDTasks::RNDCQueue->new() ],
    );
}

1;
__END__

=encoding utf-8

=head1 NAME

Cpanel::TaskProcessors::BINDTasks - Task processor for restarting BIND

=head1 VERSION

This document describes Cpanel::TaskProcessors::BINDTasks version 0.0.3


=head1 SYNOPSIS

    use Cpanel::TaskProcessors::BINDTasks;

=head1 DESCRIPTION

Implement the code for the I<rndc> Tasks. These
are not intended to be used directly.

=head1 INTERFACE

This module defines two subclasses of L<Cpanel::TaskQueue::FastSpawn> and a package method.

=head2 Cpanel::TaskProcessors::BINDTasks::to_register

Used by the L<Cpanel::TaskQueue::PluginManager> to register the included classes.

=over

=item $proc->is_valid_args( $task )

Validates the number of arguments for the rndc reload and rndc reconfig calls

=back

=head2 Cpanel::TaskProcessors::BINDTasks::RNDC

Runs rndc reload or rndc reconfig
Implements the following methods:

=head1 DIAGNOSTICS

=over

=item C<< The system could not locate “rndc” >>

If rndc is missing, the error message is logged.

=back

=head1 CONFIGURATION AND ENVIRONMENT

Cpanel::TaskProcessors::BINDTasks assumes that the environment has been made
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
