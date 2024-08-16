package Cpanel::Exception::Database::MysqlIllegalCollations;

# cpanel - Cpanel/Exception/Database/MysqlIllegalCollations.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Exception::Database::MysqlIllegalCollations

=head1 DESCRIPTION

This exception class represents MySQL “illegal collation” failures:
C<ER_CANT_AGGREGATE_3COLLATIONS> and C<ER_CANT_AGGREGATE_NCOLLATIONS>.

=cut

#----------------------------------------------------------------------

use parent qw( Cpanel::Exception );

1;
