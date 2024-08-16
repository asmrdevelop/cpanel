package Cpanel::Server::Logs;

# cpanel - Cpanel/Server/Logs.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Logger::Persistent ();
use Cpanel::ConfigFiles        ();
use Cpanel::LoadModule         ();

# For testing..
our $LOG_ROOT = $Cpanel::ConfigFiles::CPANEL_ROOT;
our $LOG_DIR  = "logs/";

########################################################
#
# Method:
#   new
#
# Description:
#   Creates a set of logger objects when provided a log table
#
# Parameters:
#   logs          - An arrayref of logs to open in the following format
#          [
#            { 'key' => logkey, 'file' => NAME_OF_LOG_FILE, 'log_pid' => 0 or 1 },
#             ...
#          ]
#          logkey   - The unique key used to identify the log (e.g., 'panic')
#          file     - The path to the log file to be created under root/logs/
#          log_pid  - Controls if the pid of the logging process is included in the log
#
# Returns:
#   A Cpanel::Server::Logs that contains Cpanel::Logger::Persistent objects
#
sub new {
    my ( $class, %OPTS ) = @_;

    my $log_table          = $OPTS{'logs'};
    my $no_load_from_cache = $OPTS{'no_load_from_cache'} ? 1 : 0;
    my $self               = bless {}, $class;

    foreach my $params ( @{$log_table} ) {
        $self->{ $params->{'key'} } = Cpanel::Logger::Persistent->new(
            {
                'alternate_logfile'  => "$LOG_ROOT/$LOG_DIR$params->{'file'}",
                'log_pid'            => ( $params->{'log_pid'} ? 1 : 0 ),
                'no_load_from_cache' => $no_load_from_cache,
            }
        );
    }

    return $self;
}

########################################################
#
# Method:
#   get
#
# Description:
#   Get a Cpanel::Logger object by key from the object
#
# Parameters:
#   The key that references the Cpanel::Logger object
#
# Exceptions:
#   dies when the key does not reference a valid object
#
# Returns:
#   A Cpanel::Logger object
#
# Notes:
#   Cpanel::AttributeProvider not used here because
#   Cpanel::Server::Logs needs to stay lightweight as we are already at the
#   peak of allowed cpsrvd memory requirements
sub get {
    return $_[0]->{ $_[1] } || do {
        Cpanel::LoadModule::load_perl_module('Cpanel::Carp');
        die Cpanel::Carp::safe_longmess("The log store does not contain the key “$_[1]”. open_logs was likely never called.");
    }
}

1;
