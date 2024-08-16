package Cpanel::Server::LogAccess;

# cpanel - Cpanel/Server/LogAccess.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

########################################################
#
# Method:
#   get_log
#
# Description:
#   Get a Cpanel::Logger object by key from the
#   internal Cpanel::Server::Logs
#
# Parameters:
#   The key that references the Cpanel::Logger object
#   inside the Cpanel::Server::Logs object
#
# Returns:
#   A Cpanel::Logger::Persitant object
#
sub get_log {    ## no critic qw(RequireArgUnpacking)
    return $_[0]->{'_logs'}->get( $_[1] );
}

########################################################
#
# Method:
#   logs
#
# Description:
#   Get the Cpanel::Server::Logs object
#
# Returns:
#   A Cpanel::Server::Logs object
#
sub logs {    ## no critic qw(RequireArgUnpacking)
    return $_[0]->{'_logs'};
}
1;
