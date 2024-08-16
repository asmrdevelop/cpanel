package Cpanel::Server::PIDFile;

# cpanel - Cpanel/Server/PIDFile.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::PIDFile

=head1 DESCRIPTION

This module exists to have a single reference for all Perl code to
get cpsrvd’s PID file.

=head1 CONSTANTS

=head2 PATH

Returns the path to cpsrvd’s PID file.

=cut

use constant PATH => '/var/run/cpsrvd.pid';

1;
