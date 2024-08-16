package Whostmgr::Transfers::Systems::Mysql::Stream::Constants;

# cpanel - Whostmgr/Transfers/Systems/Mysql/Stream/Constants.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::Systems::Mysql::Stream::Constants

=head1 SYNOPSIS

    my $max_secs = Whostmgr::Transfers::Systems::Mysql::Stream::Constants::MYSQL_QUERY_TIMEOUT;

=head1 DESCRIPTION

This module contains constants that pertain to streaming MySQL
for transfers.

=cut

#----------------------------------------------------------------------

# This value MUST accommodate commands like ENABLE KEYS, which can take
# several minutes on a large DB.
#
use constant MYSQL_QUERY_TIMEOUT => 3600;

#----------------------------------------------------------------------

=head1 CONSTANTS

=head2 MYSQL_QUERY_TIMEOUT

The maximum number of seconds to wait for MySQL to execute a single
statement.

=cut

1;
