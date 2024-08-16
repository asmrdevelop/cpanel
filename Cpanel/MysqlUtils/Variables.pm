package Cpanel::MysqlUtils::Variables;

# cpanel - Cpanel/MysqlUtils/Variables.pm             Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::MysqlUtils::Connect ();

=encoding utf-8

=head1 NAME

Cpanel::MysqlUtils::Variables - Fetch mysql variables

=head1 SYNOPSIS

    use Cpanel::MysqlUtils::Variables;

    my $mysqltmpdir = Cpanel::MysqlUtils::Variables::get_mysql_variable('tmpdir');

=head1 FUNCTIONS

=head2 get_mysql_variable($var)

Fetch a mysql variable value.

=cut

sub get_mysql_variable {
    my ($var) = @_;

    require Cpanel::MysqlUtils::Connect;

    my $dbh = Cpanel::MysqlUtils::Connect::get_dbi_handle();

    # If this doesn’t work, try INFORMATION_SCHEMA.
    my ($val) = $dbh->selectrow_array("SELECT \@\@$var");

    return $val;
}

1;
