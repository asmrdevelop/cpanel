package Cpanel::Config::Constants::PostgreSQL;

# cpanel - Cpanel/Config/Constants/PostgreSQL.pm   Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 NAME

Cpanel::PostgreSQL::Constants

=head1 DESCRIPTION

This module houses constants that are useful for working with PostgreSQL.

=head1 CONSTANTS

=head2 TIMEOUT_POSTGRESQLDUMP

How many seconds to wait before timing out on a database dump.

=cut

# 3 hours time limit when fetching postgres dump
our $TIMEOUT_POSTGRESQLDUMP = 10800;

1;
