package Cpanel::DBI::Mysql::Utils::Backend;

# cpanel - Cpanel/DBI/Mysql/Utils/Backend.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::DBI::Mysql::Utils::Backend

=head1 DESCRIPTION

This module defines interfaces for pieces of L<Cpanel::DBI::Mysql::Utils>’s logic
to facilitate testing.

Please do not reuse this module outside of Cpanel::DBI::Mysql::Utils! Instead,
refactor the logic that interests you, and call that module from this one.

=cut

#----------------------------------------------------------------------

use Cpanel::MysqlUtils::Quote   ();
use Cpanel::MysqlUtils::Unquote ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 quote_fix ( $user, $host, $statement )

If you are on MySQL 8 or MariaDB 10.3, you will have interesting
behavior where account names -e.g. 'user'@'host'- in SHOW GRANTS output
use backticks instead of single quotes. Since older versions of cPanel
won't understand this, we need to convert these backticks to single
quotes.

Returns a valid GRANT statement.

=cut

sub quote_fix ( $user, $host, $statement ) {
    my ( $quoted_user, $quoted_host ) = $statement =~ qr/($Cpanel::MysqlUtils::Unquote::QUOTED_IDENTIFIER_REGEXP)@($Cpanel::MysqlUtils::Unquote::QUOTED_IDENTIFIER_REGEXP)/;
    if ( $quoted_user && $quoted_host ) {
        ( $quoted_user, $quoted_host ) = map { Cpanel::MysqlUtils::Quote::quote( Cpanel::MysqlUtils::Unquote::unquote_identifier($_) ) } ( $user, $host );
        $statement =~ s/$Cpanel::MysqlUtils::Unquote::QUOTED_IDENTIFIER_REGEXP\@$Cpanel::MysqlUtils::Unquote::QUOTED_IDENTIFIER_REGEXP/$quoted_user\@$quoted_host/;
    }

    return $statement;
}

1;
