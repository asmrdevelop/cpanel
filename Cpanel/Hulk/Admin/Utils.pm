package Cpanel::Hulk::Admin::Utils;

# cpanel - Cpanel/Hulk/Admin/Utils.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::Hulk    ();
use Cpanel::Hulk::Admin     ();
use Cpanel::Hulk::Admin::DB ();

###########################################################################
#
# Method:
#   clear_bad_logins_and_temp_bans_for_user
#
# Description:
#   This function is used to clear temp bans and bad logins for users who have had their passwords reset when they have
#   entered too many bad passwords and locked themselves out of their accounts. This function performs no action if
#   hulk is not enabled.
#
# Parameters:
#   $user - The name of the user to clear bad logins and temp bans for.
#
# Exceptions:
#   Cpanel::Exception - An exception is thrown if flush_bad_login_history_for_user cannot act on the cphulk database.
#
# Returns:
#   The method returns 1 on success or throws an exception if it failed.
#
sub clear_bad_logins_and_temp_bans_for_user {
    my ($user) = @_;

    if ( Cpanel::Config::Hulk::is_enabled() ) {
        my $hulk_dbh = Cpanel::Hulk::Admin::DB::get_dbh();

        if ($hulk_dbh) {
            Cpanel::Hulk::Admin::clear_tempbans_for_user( $hulk_dbh, $user );
            Cpanel::Hulk::Admin::flush_bad_login_history_for_user( $hulk_dbh, $user );
        }
    }

    return 1;
}

1;
