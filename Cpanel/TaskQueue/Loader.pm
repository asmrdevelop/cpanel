package Cpanel::TaskQueue::Loader;

# cpanel - Cpanel/TaskQueue/Loader.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::TaskQueue::Loader - Load the Cpanel::TaskQueue modules with the correct serializer and locker.

=head1 SYNOPSIS

    my $logger = Cpanel::LoggerAdapter->new( { alternate_logfile => $logfile } );

    Cpanel::TaskQueue::Loader::load_taskqueue_modules($logger);

=cut

=head2 load_taskqueue_modules($logger)

Load the Cpanel::TaskQueue modules with the correct serializer and locker.

The $logger arugument is a Cpanel::TaskQueue logger and NOT a
Cpanel::Logger.  Use Cpanel::LoggerAdapter if you want Cpanel::Logger functionality.

=cut

sub load_taskqueue_modules ($logger) {
    die 'Usage: load_taskqueue_modules($logger)' if !$logger;
    if ( !$INC{'Cpanel/StateFile.pm'} || !$INC{'Cpanel/TaskQueue.pm'} ) {
        no warnings 'redefine';
        no warnings 'once';
        my $has_posix = $INC{'POSIX.pm'} ? 1 : 0;
        local $INC{'POSIX.pm'} = '__MOCK__' if !$has_posix;
        local *POSIX::WNOHANG = sub { return 1; }
          if !$has_posix;

        if ( !$INC{'Cpanel/StateFile.pm'} ) {
            require Cpanel::StateFile;    # PPI USE OK -- Code imported from GitHub
            require Cpanel::SafeFile::FileLocker;

            my $filelocker = Cpanel::SafeFile::FileLocker->new( { 'logger' => $logger } );
            'Cpanel::StateFile'->import( '-filelock' => $filelocker, '-logger' => $logger );
        }

        # scheduler is going to be loaded by Cpanel::TaskQueue, we also want to set the correct serializer
        if ( !$INC{'Cpanel/TaskQueue.pm'} ) {
            my $was_using_scheduler = $INC{'Cpanel/TaskQueue/Scheduler.pm'} ? 1 : 0;

            require Cpanel::TaskQueue;
            if ( !$was_using_scheduler && $INC{'Cpanel/TaskQueue/Scheduler.pm'} ) {
                Cpanel::TaskQueue::Scheduler->import;
            }
        }
    }

    require Cpanel::TaskQueue::Scheduler::DupeSupport;    # PPI USE OK - used later
    require Cpanel::TaskQueue::PluginManager;             # PPI USE OK - used later

    return 1;
}

1;
