package Cpanel::MysqlUtils::Support;

# cpanel - Cpanel/MysqlUtils/Support.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::MysqlUtils::Support - Determine if specific MySQL features are supported

=head1 SYNOPSIS

    use Cpanel::MysqlUtils::Support;

    Cpanel::MysqlUtils::Support::server_supports_show_create_trigger($dbh);

    Cpanel::MysqlUtils::Support::server_supports_events($dbh);

=cut

=head2 server_supports_show_create_trigger($dbh)

Determine if the server connected on $dbh supports
SHOW CREATE TRIGGER

=cut

sub server_supports_show_create_trigger {
    my ($dbh) = @_;

    #https://dev.mysql.com/doc/refman/5.1/en/show-create-trigger.html
    return $dbh->{'mysql_serverversion'} >= 50121 ? 1 : 0;
}

=head2 server_supports_events($dbh)

Determine if the server connected on $dbh supports events

=cut

sub server_supports_events {
    my ($dbh) = @_;

    return $dbh->{'mysql_serverversion'} >= 50106 ? 1 : 0;
}

=head2 server_uses_mariadb_ambiguous_SET_PASSWORD( $DBH_OR_VERSION_NUMBER )

Determine if the server’s C<SET PASSWORD> is ambiguous as to which
C<mysql.user> column it updates, as per MariaDB.

The input can be either a DBI handle or a version number string in “long”
form, e.g, C<10.2.16>.

See L<https://github.com/MariaDB/server/commit/5f0510225aa149377b8563f6e96b74d05d41f080#diff-dca2f11b2511ceff9960dc3bcd972d04> and L<https://jira.mariadb.org/browse/MDEV-16238>
for more background on this strangeness.

=cut

sub server_uses_mariadb_ambiguous_SET_PASSWORD {
    my ($dbh_or_version_number) = @_;

    if ( ref $dbh_or_version_number ) {
        return $dbh_or_version_number->{'mysql_serverversion'} >= 100216 ? 1 : 0;
    }

    require Cpanel::MysqlUtils::Version;
    return Cpanel::MysqlUtils::Version::is_at_least( $dbh_or_version_number, '10.2.16' );
}

#----------------------------------------------------------------------

=head2 server_can_lock_accounts( $DBH )

Returns a boolean that indicates whether the MySQL server supports
account locking.

=cut

sub server_can_lock_accounts {
    my ($dbh) = @_;

    return 0 if $dbh->server_is_mariadb();
    return 0 if $dbh->{'mysql_serverversion'} < 50706;

    return 1;
}

1;
