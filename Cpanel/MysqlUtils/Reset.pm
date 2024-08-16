package Cpanel::MysqlUtils::Reset;

# cpanel - Cpanel/MysqlUtils/Reset.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;
use Cpanel::Database ();
use Sys::Hostname    ();

# Note: MariaDB signs this value so it will be -1 when upgrading
our $MAX_SIGNED_INT = '2147483647';    # https://dev.mysql.com/doc/refman/5.0/en/integer-types.html

# This function resets all of 'root's mySQL/MariaDB limits to a sane value
# this is important because MariaDB uses a signed int whereas MySQL uses
# an unsigned on which will result in it overflowing.  Since we set this value
# to the unsigned int in 11.44+, we need to update it now.
sub set_root_maximums_to_sane_values () {
    my $db_obj = Cpanel::Database->new();

    # Case 107665:
    # Ensure root always has an effectively 'unlimited' number of connections
    # to the mySQL server.
    #
    # A given OS can have entries for one, some, or all of these hosts.
    #   If there is not an entry for a given $host it is not created, its eseentially a noop.
    # If the admin adds root@something-else those will not change.
    #   That may be what the admin wants or it could be problematic.
    #   It can cause the unit test to fail (e.g. ZC-11243) or
    #   worse NOT fail leaving us to our assumptions that all is well.
    foreach my $host ( qw(localhost ::1 127.0.0.1), Sys::Hostname::hostname() ) {
        $db_obj->set_user_resource_limits(
            'user'                 => 'root',
            'host'                 => $host,
            'max_user_connections' => $MAX_SIGNED_INT,
            'max_updates'          => $MAX_SIGNED_INT,
            'max_connections'      => $MAX_SIGNED_INT,
            'max_questions'        => $MAX_SIGNED_INT,
        );
    }

    return;
}

1;
