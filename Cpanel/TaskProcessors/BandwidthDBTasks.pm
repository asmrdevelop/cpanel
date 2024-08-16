package Cpanel::TaskProcessors::BandwidthDBTasks;

# cpanel - Cpanel/TaskProcessors/BandwidthDBTasks.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

{

    package Cpanel::TaskProcessors::BandwidthDBTasks::Create;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    use Cpanel::LoadModule ();

    use Try::Tiny;

    # TODO: allow the domain to be passed as a second argument
    # This is not needed for account creation so it will be
    # done at a later date
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
        Cpanel::LoadModule::load_perl_module('Cpanel::BandwidthDB::Create');
        Cpanel::LoadModule::load_perl_module('Cpanel::AcctUtils::Domain');

        try {
            my $domain = Cpanel::AcctUtils::Domain::getdomain($user);
            my $bwdb   = Cpanel::BandwidthDB::Create->new($user);
            $bwdb->initialize_domain($domain);
            $bwdb->force_install();
        }
        catch {
            Cpanel::Debug::log_warn($_);
        };

        return 1;
    }
}

{

    package Cpanel::TaskProcessors::BandwidthDBTasks::RootCache;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    use Cpanel::LoadModule ();

    use Try::Tiny;

    sub is_valid_args {
        my ( $self, $task ) = @_;
        my $numargs = scalar $task->args();
        return 0 if $numargs != 1;
        my ($user) = $task->args();
        require Cpanel::AcctUtils::Account;
        return 1 if Cpanel::AcctUtils::Account::accountexists($user);
        return 0;
    }

    sub _do_child_task {
        my ( $self, $task ) = @_;
        my ($user) = $task->args();

        require Cpanel::Debug;
        require Cpanel::BandwidthDB;
        require Cpanel::BandwidthDB::RootCache;
        require Cpanel::Timezones;

        # This prevents endlessly stating /etc/localtime
        local $ENV{'TZ'} = Cpanel::Timezones::calculate_TZ_env();
        #
        # We could get multiple users importing in a single DB open
        # if we did a subqueue, however that would tie up the RootCache
        # for longer so its likely not worth doing at this point
        try {
            my $bwdb = Cpanel::BandwidthDB::get_reader_for_root($user);
            my $obj  = Cpanel::BandwidthDB::RootCache->new();
            my $dbh  = $obj->{'_dbh'};

            #Wrapping this in a transaction was ~3x speed up
            #since there can be 80000+ executes
            $dbh->do('BEGIN TRANSACTION');
            $obj->import_from_bandwidthdb($bwdb);
            $dbh->do('COMMIT TRANSACTION');

        }
        catch {
            Cpanel::Debug::log_warn($_);
        };

        return 1;
    }

    sub deferral_tags {

        # only allow one rootcache import at a time
        return qw/bandwidthdb_rootcache/;
    }
}

sub to_register {
    return (
        [ 'create_bandwidthdb',   Cpanel::TaskProcessors::BandwidthDBTasks::Create->new() ],
        [ 'build_bwdb_rootcache', Cpanel::TaskProcessors::BandwidthDBTasks::RootCache->new() ],

    );
}

1;
__END__

=head1 NAME

Cpanel::TaskProcessors::BandwidthDBTasks - Task processor for BandwidthDB

=head1 VERSION

This document describes Cpanel::TaskProcessors::BandwidthDBTasks version 0.0.3


=head1 SYNOPSIS

    use Cpanel::TaskProcessors::BandwidthDBTasks;

=head1 DESCRIPTION

Implement the code for the I<create_bandwidthdb> task. These
are not intended to be used directly.

=head1 INTERFACE

This module defines one subclass of L<Cpanel::TaskQueue::FastSpawn> and a package method.

=head2 Cpanel::TaskProcessors::BandwidthDBTasks::to_register

Used by the L<Cpanel::TaskQueue::PluginManager> to register the included classes.

=head2 Cpanel::TaskProcessors::BandwidthDBTasks::Create

This class creates bandwidth database for the users's main domain
Implemented methods are:

=over 4

=item $proc->is_valid_args( $task )

Returns true if the task has no arguments or only the C<user> argument.

=back

=head2 Cpanel::TaskProcessors::BandwidthDBTasks::RootCache

This class refreshing the RootCache with the user's current bandwidth usage
Implemented methods are:

=over 4

=item $proc->is_valid_args( $task )

Returns true if the task has no arguments or only the C<user> argument.

=back


=head1 CONFIGURATION AND ENVIRONMENT

Cpanel::TaskProcessors::BandwidthDBTasks assumes that the environment has been made
safe before any of the tasks are executed.

=head1 INCOMPATIBILITIES

None reported.

=head1 BUGS AND LIMITATIONS

No bugs have been reported.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2016, cPanel, Inc. All rights reserved.
