package Cpanel::Email::Accounts::Cache;

# cpanel - Cpanel/Email/Accounts/Cache.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

#----------------------------------------------------------------------
# Verify that the given DB cache is up-to-date as per the given mtimes.
# (NB: This logic is pretty tightly coupled to C::E::Accounts.)
#
# Arguments:
#
#   - DB cache reference, as in $popdbref->{$domain} in
#     Cpanel::Email::Accounts::manage_email_accounts_db()
#
#   - The earliest valid timestamp
#
#   - The latest valid timestamp (probably time())
#
#   - key/value pairs of (key => source_mtime); source_mtime can be undef
#     The keys correspond to the given domain DB cache reference.
#     The values are the associated mtime of the authoritative datastore.
#
sub can_skip_sync {
    my ( $dbref, $earliest, $latest, @mtimes_to_check ) = @_;

    my $skip_sync = 0;

  CAN_SKIP: {
        while ( my ( $key, $source_mtime ) = splice( @mtimes_to_check, 0, 2 ) ) {

            #The cache must have a defined entry for this key.
            last CAN_SKIP if !defined $dbref->{$key};

            # db mtime is greater than or equal to the mtime of the source file
            if ($source_mtime) {
                last CAN_SKIP if $dbref->{$key} < $source_mtime;
            }

            # db mtime is time warp safe
            last CAN_SKIP if $dbref->{$key} > $latest;

            # db mtime is not past the ttl ($ttl)
            last CAN_SKIP if $dbref->{$key} < $earliest;
        }

        $skip_sync = 1;
    }

    return $skip_sync;
}

1;
