package Cpanel::MysqlUtils::Compat::Suspension;

# cpanel - Cpanel/MysqlUtils/Compat/Suspension.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::MysqlUtils::Compat::Suspension

=head1 SYNOPSIS

    Cpanel::MysqlUtils::Compat::Suspension::normalize_suspension($dbh);

=head1 DESCRIPTION

Compatibility logic for MySQL regarding account suspensions.

=cut

#----------------------------------------------------------------------

use Cpanel::MysqlUtils::Support ();

#for testing
our $_MYSQL_DB = 'mysql';

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $number_changed = normalize_suspension( $DBH )

This ensures that the account suspension/locking mechanism in play
for each suspended MySQL account (i.e., user/host combination)
matches the DB server version.

$DBH is a DBI handle from L<Cpanel::DBI::Mysql>. The return is the
number of accounts changed, or undef if the MySQL server doesn’t
support account locking.

It is anticipated that this logic will only be needed when migrating to a
DB server version that supports account locking.

=cut

sub normalize_suspension {
    my ($dbh) = @_;

    return undef if !_can_lock_accounts($dbh);

    my $changed_ct = 0 + $dbh->do( _QUERY() );

    # Without this, MySQL 5.7 will refuse to unlock an account.
    $dbh->do('FLUSH PRIVILEGES') if $changed_ct;

    return $changed_ct;
}

sub _QUERY {
    return qq<
        UPDATE $_MYSQL_DB.user
        SET
            account_locked = 'Y',
            authentication_string = CONCAT( '', '*', REVERSE( SUBSTR(authentication_string,2) ) )
        WHERE
            INSTR(authentication_string,'-') = 1
    >;
}

# mocked & referenced in tests
*_can_lock_accounts = \*Cpanel::MysqlUtils::Support::server_can_lock_accounts;

1;
