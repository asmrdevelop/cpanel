package Cpanel::Server::WebSocket::whostmgr::PluginLog;

# cpanel - Cpanel/Server/WebSocket/whostmgr/PluginLog.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::WebSocket::whostmgr::PluginLog

=head1 SYNOPSIS

See the documentation in L<Cpanel::Server::Handlers::WebSocket>.

=head1 DESCRIPTION

This module streams a plugin installation/uninstallation log file.

It expects the following C<$ENV{'QUERY_STRING'}> with HTML query
parameters:

=over

=item * C<log_entry> - Required. The log entry to stream.

=item * C<pid> - Optional. If given, this module will monitor the log file
for updates until the indicated process is finished. If not given, the
file’s contents will be read once, then the connection will be closed.

=back

=cut

use parent qw( Cpanel::Server::WebSocket::whostmgr::LogStreamer );

use Cpanel::Plugins::Log               ();
use Cpanel::ProcessLog::WithChildError ();

$Cpanel::ProcessLog::WithChildError::DIR = $Cpanel::Plugins::Log::_DIR;

1;
