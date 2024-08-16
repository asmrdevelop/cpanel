package Whostmgr::Transfers::Session::Preflight::Restore;

# cpanel - Whostmgr/Transfers/Session/Preflight/Restore.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Services::Available ();

use Try::Tiny;

# Note: MariaDB signs this value so it will be -1 when upgrading from MySQL where
# we had previously used the UNSIGNED MAXIMUM from:
# https://dev.mysql.com/doc/refman/5.0/en/integer-types.html
#
# We know used the SIGNED MAXIMUM from:
# https://mariadb.com/kb/en/mariadb/documentation/data-types/data-types-numeric-data-types/int/
my $MAX_SIGNED_INT = '2147483647';

sub ensure_mysql_is_sane_for_restore {

    my (%vals) = @_;

    require Cpanel::Services::Enabled;
    if ( Cpanel::Services::Enabled::is_provided("mysql") ) {

        my ( $status, $statusmsg ) = Cpanel::Services::Available::ensure_sql_servers_are_available();
        return ( $status, $statusmsg ) if !$status;

        # Must happen after disconnect
        my ($err);
        try {
            require Cpanel::MysqlUtils::MyCnf::Adjust;
            Cpanel::MysqlUtils::MyCnf::Adjust::auto_adjust(
                { 'verbose' => 0, 'interval' => $Cpanel::MysqlUtils::MyCnf::Adjust::DEFAULT_INTERVAL },
                {
                    'OpenFiles'        => { 'min-value' => $vals{'open-files-limit'}   || 0 },
                    'MaxAllowedPacket' => { 'min-value' => $vals{'max-allowed-packet'} || 0 },
                }
            );
        }
        catch {
            $err = $_;
        };

        if ($err) {
            require Cpanel::Exception;
            return ( 0, Cpanel::Exception::get_string($err) );
        }

        try {
            require Cpanel::MysqlUtils::Reset;
            Cpanel::MysqlUtils::Reset::set_root_maximums_to_sane_values();
        }
        catch {
            $err = $_;
        };

        if ($err) {
            require Cpanel::Exception;
            return ( 0, Cpanel::Exception::get_string($err) );
        }

    }

    return ( 1, 'ok' );
}

1;
